#!/usr/bin/env bash
# 接口触达统计。
#
# 为什么要有这个脚本：README 里出现的覆盖率必须能被复算。手写「约 80%」
# 是最容易被一句话打掉的东西——分母怎么挑的、分子含不含运算符，全都不在场。
# 这里把两件事都钉死：
#   分母 = 核心库 .mbti 里的 `pub fn` 行数（可数，随核心库版本变化）；
#   分子 = probes/api-touch.txt 里登记的符号，逐个校验后去重。
#
# 分子要过四道校验，任何一道不过就退出 1：
#   1. 该符号确实出现在对应包的 pkg.generated.mbti（不能编接口）；
#   2. 该符号的名字确实出现在 probes 源码里（不能登记没调过的东西）；
#   3. 用例名确实在 probes 的 case 列表里（不能登记不存在的 case）；
#   4. 该符号出现在**这条用例自己的函数体**里（via: 时是其辅助函数体），
#      不能拿别的 case 的调用充数。
#
# 分母口径：builtin 只计 String / Double / Char / BytesView 的方法。
# 其余 700+ 个函数（数组、迭代器、JSON、格式化工具……）与本项目的被测面无关，
# 既不计入分母，也不假装覆盖——docs/SCOPE.md 写了为什么不覆盖它们。
#
# 用法：bash scripts/coverage.sh [--quiet|--check]
#   --quiet  只输出汇总行（供外部引用）
#   --check  README 里「接口触达：」那一行必须与本次算出来的逐字一致，否则退出 1

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

CORE="${CORE:-$HOME/.moon/lib/core}"
MANIFEST="probes/api-touch.txt"
QUIET=0
case "${1:-}" in
  --quiet) QUIET=1 ;;
  --check) QUIET=2 ;;
  "") ;;
  *) echo "未知参数：$1" >&2; exit 2 ;;
esac

if [ ! -d "$CORE" ]; then
  echo "错误：找不到核心库目录 $CORE（可用 CORE=... 指定）" >&2
  exit 2
fi
if [ ! -f "$MANIFEST" ]; then
  echo "错误：找不到清单 $MANIFEST" >&2
  exit 2
fi

mbti_of() {
  case "$1" in
    builtin) echo "$CORE/builtin/pkg.generated.mbti" ;;
    *) echo "$CORE/$1/pkg.generated.mbti" ;;
  esac
}

# 分母：builtin 按类型前缀过滤，其余包全量。
denominator_of() {
  local pkg="$1" f
  f=$(mbti_of "$pkg")
  if [ ! -f "$f" ]; then
    echo "-1"
    return
  fi
  case "$pkg" in
    builtin) grep -cE '^pub fn (String|Double|Char|BytesView)::' "$f" ;;
    *) grep -c '^pub fn' "$f" ;;
  esac
}

# 取某个 probe 函数（case 或辅助函数）的函数体。
fn_body() {
  awk -v want="fn $1(" '
    index($0, want) { inside = 1; print; next }
    inside && /^}/ { inside = 0; next }
    inside { print }
  ' probes/*.mbt
}

CASES=$(moon run probes --target wasm -- list 2>/dev/null)
if [ -z "$CASES" ]; then
  echo "错误：拿不到 probes 的 case 列表（moon run probes -- list 失败）" >&2
  exit 2
fi

ERRORS=0
fail() {
  echo "  ✗ $*" >&2
  ERRORS=$((ERRORS + 1))
}

# 校验每条登记，并把校验通过的符号按包去重收集。
mkdir -p .moondiff-out
tmp=".moondiff-out/api-touch.check"
: > "$tmp"
while IFS='|' read -r pkg sym case_name via; do
  case "${pkg:-}" in ''|\#*) continue ;; esac
  [ -z "${sym:-}" ] && continue
  [ -z "${case_name:-}" ] && {
    fail "缺用例名：$pkg|$sym"
    continue
  }
  mbti=$(mbti_of "$pkg")
  grep -qF "pub fn $sym(" "$mbti" 2>/dev/null ||
    fail "$sym 不在 $pkg 的 .mbti 里"
  bare="${sym##*::}"
  grep -qF "$bare(" probes/*.mbt ||
    fail "$sym 在探针源码里没有被调用"
  printf '%s\n' "$CASES" | grep -qx "$case_name" ||
    fail "用例 $case_name 不在 probes 的 case 列表里"
  fn="case_$(printf '%s' "$case_name" | tr '-' '_')"
  if [ -n "${via:-}" ]; then
    hay=$(fn_body "${via#via:}")
  else
    hay=$(fn_body "$fn")
  fi
  printf '%s' "$hay" | grep -qF "$bare(" ||
    fail "$sym 不在 $fn 的函数体里（登记与用例对不上）"
  printf '%s|%s\n' "$pkg" "$sym" >> "$tmp"
done < "$MANIFEST"

if [ "$ERRORS" -gt 0 ]; then
  echo "" >&2
  echo "共 $ERRORS 处登记不成立，覆盖率不予计算。" >&2
  exit 1
fi

# 去重后按包统计。
PKGS="bigint builtin encoding/utf8 encoding/hex encoding/base64 encoding/ascii"
rows=""
tot_den=0
tot_hit=0
for pkg in $PKGS; do
  den=$(denominator_of "$pkg")
  hit=$(grep -c "^$pkg|" "$tmp" 2>/dev/null || true)
  uniq=$(grep "^$pkg|" "$tmp" 2>/dev/null | cut -d'|' -f2 | sort -u | wc -l | tr -d ' ')
  hit=$uniq
  [ "$den" = "-1" ] && continue
  pct=$(awk -v a="$hit" -v b="$den" 'BEGIN{ if (b>0) printf "%.1f", 100*a/b; else printf "0.0" }')
  rows="$rows$(printf '| %-19s | %6s | %6s | %6s%% |\n' "$pkg" "$den" "$hit" "$pct")"$'\n'
  tot_den=$((tot_den + den))
  tot_hit=$((tot_hit + hit))
done
tot_pct=$(awk -v a="$tot_hit" -v b="$tot_den" 'BEGIN{ printf "%.1f", 100*a/b }')

n_lines=$(grep -vc '^\s*\(#\|$\)' "$MANIFEST")
n_syms=$(cut -d'|' -f1,2 "$tmp" | sort -u | wc -l | tr -d ' ')
n_cases=$(printf '%s\n' "$CASES" | wc -l | tr -d ' ')
c_bigint=$(printf '%s\n' "$CASES" | grep -c '^bigint-')
c_double=$(printf '%s\n' "$CASES" | grep -c '^double-')
c_string=$(printf '%s\n' "$CASES" | grep -c '^string-')
c_base64=$(printf '%s\n' "$CASES" | grep -c '^base64-')

# README 里必须逐字出现的那一行。--check 拿它跟实际算出来的比。
README_LINE="接口触达：$tot_hit / $tot_den = $tot_pct%（$n_cases 个用例：bigint $c_bigint / double $c_double / string $c_string / base64 $c_base64）"

if [ "$QUIET" -eq 2 ]; then
  # --check：README 的数字必须与脚本算出来的一致，否则失败。
  if [ ! -f README.md ]; then
    echo "错误：找不到 README.md" >&2
    exit 2
  fi
  actual=$(grep -m1 '^接口触达：' README.md || true)
  if [ "$actual" != "$README_LINE" ]; then
    echo "README 与脚本输出不一致：" >&2
    echo "  脚本  : $README_LINE" >&2
    echo "  README: ${actual:-（没有以「接口触达：」开头的行）}" >&2
    echo "先跑 bash scripts/coverage.sh，再把那一行原样贴进 README。" >&2
    exit 1
  fi
  echo "README 与脚本一致：$README_LINE"
  exit 0
fi

if [ "$QUIET" -eq 0 ]; then
  echo "== MoonDiff 接口触达统计 =="
  echo "核心库   : $CORE"
  echo "清单     : $MANIFEST（$n_lines 条登记，$n_syms 个不同符号）"
  echo "分母口径 : .mbti 的 \`pub fn\` 行；builtin 只计 String/Double/Char/BytesView"
  echo
  # 表格全 ASCII：中文宽度在不同终端不一样，表格一歪就没人信数字。
  printf '+---------------------+--------+--------+---------+\n'
  printf '| %-19s | %6s | %6s | %7s |\n' "package" "public" "touched" "ratio"
  printf '+---------------------+--------+--------+---------+\n'
  printf '%s' "$rows"
  printf '+---------------------+--------+--------+---------+\n'
  printf '| %-19s | %6s | %6s | %6s%% |\n' "TOTAL" "$tot_den" "$tot_hit" "$tot_pct"
  printf '+---------------------+--------+--------+---------+\n'
  echo
  echo "用例数   : $n_cases"
  echo "用例分布 : bigint $c_bigint / double $c_double / string $c_string / base64 $c_base64"
  echo
  echo "README 应逐字包含："
  echo "  $README_LINE"
  echo
  echo "参照（不计入分母）：builtin 全部公开函数 $(grep -c '^pub fn' "$CORE/builtin/pkg.generated.mbti") 个，"
  echo "  本项目只声明 String/Double/Char/BytesView 的方法为被测面，其余不覆盖。"
else
  printf 'TOUCHED %s/%s (%s%%) cases=%s\n' "$tot_hit" "$tot_den" "$tot_pct" "$n_cases"
fi
