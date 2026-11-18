#!/usr/bin/env bash
# 源码探针：同一份 MoonBit 源码在多个后端执行，逐字节比对 stdout。
#
# 与 matrix.sh 的分工：
#   matrix.sh        跑「规格程序」（JSON，可生成、可收缩、可定位到步）
#   source-probe.sh  跑「源码探针」（普通 MoonBit，直接 import 真实包）
#
# 探针本身不依赖本项目任何代码——它只 import moonbitlang/core。
# 这条约束由 tests/source-expected.txt 的说明与 README 一起保证：
# 如果探针需要 DSL 才能写，这个脚本就没有存在意义。
#
# 用法：
#   scripts/source-probe.sh                  # 全部 case，打印矩阵
#   scripts/source-probe.sh bigint-mul       # 只跑一个 case
#   scripts/source-probe.sh --check          # 与基线比对，新增差异才失败
#   scripts/source-probe.sh --check-ascii    # 断言所有输出是纯 ASCII
#   scripts/source-probe.sh --update         # 重写基线（必须说明理由）
#   scripts/source-probe.sh --list           # 列出全部 case

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

MOON="${MOON:-moon}"
OUT=".moondiff-out/source"
BASELINE="tests/source-expected.txt"
mkdir -p "$OUT"

MODE="report"
FILTER=""
REQUIRE_ALL=0
for a in "$@"; do
  case "$a" in
    --check) MODE="check" ;;
    --check-ascii) MODE="ascii" ;;
    --update) MODE="update" ;;
    --list) MODE="list" ;;
    --require-all) REQUIRE_ALL=1 ;;
    --*) echo "未知参数: $a" >&2; exit 2 ;;
    *) FILTER="$a" ;;
  esac
done

# 后端探测：能跑通 `list` 才算可用。缺工具链时标 unavailable，不冒充 PASS。
BACKENDS=(wasm wasm-gc js native)
AVAILABLE=()
UNAVAILABLE=()
for t in "${BACKENDS[@]}"; do
  if $MOON run probes --target "$t" -- list > "$OUT/list-$t.txt" 2> "$OUT/probe-$t.err"; then
    AVAILABLE+=("$t")
  else
    UNAVAILABLE+=("$t")
  fi
done

if [ "${#AVAILABLE[@]}" -lt 2 ]; then
  echo "错误：可用后端不足 2 个（${AVAILABLE[*]:-无}），无法做差分比较。" >&2
  echo "      native 需要 MSVC（Windows）或 gcc（Linux/macOS），缺失属预期。" >&2
  exit 3
fi

# CI 用：四后端必须全部可用，不允许某个后端被静默跳过。
if [ "$REQUIRE_ALL" = "1" ] && [ "${#AVAILABLE[@]}" -lt "${#BACKENDS[@]}" ]; then
  echo "错误：--require-all 要求四个后端全部可用，实际只有 ${AVAILABLE[*]}。" >&2
  echo "      缺: ${UNAVAILABLE[*]}" >&2
  for t in "${UNAVAILABLE[@]}"; do
    echo "  --- $t ---" >&2
    tail -3 "$OUT/probe-$t.err" >&2
  done
  exit 5
fi

CASES=$($MOON run probes --target "${AVAILABLE[0]}" -- list)
if [ -n "$FILTER" ]; then
  CASES=$(printf '%s\n' "$CASES" | grep -x -- "$FILTER")
fi
if [ -z "${CASES:-}" ]; then
  echo "没有匹配的 case（用 --list 查看全部）" >&2
  exit 2
fi

if [ "$MODE" = "list" ]; then
  printf '%s\n' "$CASES"
  exit 0
fi

# 逐 case × 逐后端执行。状态只有四种：
#   PASS / DIVERGENT / ABORT / unavailable
declare -A ST
BAD_ASCII=0

for c in $CASES; do
  base=""
  for t in "${AVAILABLE[@]}"; do
    f="$OUT/$c.$t.txt"
    if $MOON run probes --target "$t" -- "$c" > "$f" 2> "$OUT/$c.$t.err"; then
      if grep -q "^$c = " "$f"; then
        ST["$c|$t"]="OK"
        if [ -z "$base" ]; then base="$t"; fi
      else
        ST["$c|$t"]="ABORT"
      fi
    else
      ST["$c|$t"]="ABORT"
    fi
  done

  # 以第一个正常完成的后端为基线比对；全部 ABORT 时没有基线。
  for t in "${AVAILABLE[@]}"; do
    if [ "${ST["$c|$t"]}" = "OK" ]; then
      if [ -n "$base" ] && ! diff -q "$OUT/$c.$base.txt" "$OUT/$c.$t.txt" > /dev/null; then
        ST["$c|$t"]="DIVERGENT"
      else
        ST["$c|$t"]="PASS"
      fi
    fi
  done

  if [ "$MODE" = "ascii" ]; then
    for t in "${AVAILABLE[@]}"; do
      f="$OUT/$c.$t.txt"
      if [ -f "$f" ] && LC_ALL=C grep -q '[^ -~]' "$f"; then
        echo "非 ASCII 输出：$c / $t"
        LC_ALL=C grep -n '[^ -~]' "$f" | head -3
        BAD_ASCII=1
      fi
    done
  fi
done

if [ "$MODE" = "ascii" ]; then
  if [ "$BAD_ASCII" -ne 0 ]; then
    echo "FAIL：探针输出必须逐字节可比，不能含非 ASCII 字符。"
    exit 1
  fi
  echo "OK：所有探针输出均为纯 ASCII（$(printf '%s\n' "$CASES" | wc -l | tr -d ' ') 个 case 已在 ${#AVAILABLE[@]} 个后端上检查）"
  exit 0
fi

# 汇总每个 case 的单一状态：ABORT > DIVERGENT > PASS
case_status() {
  local c="$1" t s worst="PASS"
  for t in "${AVAILABLE[@]}"; do
    s="${ST["$c|$t"]}"
    if [ "$s" = "ABORT" ]; then
      worst="ABORT"
    elif [ "$s" = "DIVERGENT" ] && [ "$worst" != "ABORT" ]; then
      worst="DIVERGENT"
    fi
  done
  printf '%s' "$worst"
}

echo "源码探针矩阵（同一份 MoonBit 源码，多后端逐字节比对）"
echo "  探针包   : probes/（只 import moonbitlang/core，不依赖本项目）"
echo "  case 数  : $(printf '%s\n' "$CASES" | wc -l | tr -d ' ')"
echo "  可用后端 : ${AVAILABLE[*]}${UNAVAILABLE[*]:+ ｜ 不可用: ${UNAVAILABLE[*]}}"
echo

W=26
line="+$(printf '%*s' $((W + 2)) '' | tr ' ' '-')"
for t in "${BACKENDS[@]}"; do line="$line+-----------"; done
line="$line+"

echo "$line"
printf "| %-${W}s " "case"
for t in "${BACKENDS[@]}"; do printf "| %-9s " "$t"; done
printf "|\n"
echo "$line"
for c in $CASES; do
  printf "| %-${W}s " "$c"
  for t in "${BACKENDS[@]}"; do
    printf "| %-9s " "${ST["$c|$t"]:-unavailable}"
  done
  printf "|\n"
done
echo "$line"

NPASS=0
NDIV=0
NABORT=0
for c in $CASES; do
  case "$(case_status "$c")" in
    PASS) NPASS=$((NPASS + 1)) ;;
    DIVERGENT) NDIV=$((NDIV + 1)) ;;
    ABORT) NABORT=$((NABORT + 1)) ;;
  esac
done
echo
echo "汇总: PASS $NPASS ｜ DIVERGENT $NDIV ｜ ABORT $NABORT ｜ unavailable ${#UNAVAILABLE[@]}"

if [ "$NDIV" -gt 0 ]; then
  echo
  echo "分歧详情（最多 3 条）："
  shown=0
  for c in $CASES; do
    [ "$(case_status "$c")" = "DIVERGENT" ] || continue
    [ "$shown" -ge 3 ] && break
    base=""
    for t in "${AVAILABLE[@]}"; do
      if [ "${ST["$c|$t"]}" = "PASS" ] && [ -z "$base" ]; then base="$t"; fi
    done
    for t in "${AVAILABLE[@]}"; do
      if [ "${ST["$c|$t"]}" = "DIVERGENT" ]; then
        echo "  [$c] $base vs $t"
        diff -u "$OUT/$c.$base.txt" "$OUT/$c.$t.txt" | sed -n '3,8p' | sed 's/^/    /'
      fi
    done
    shown=$((shown + 1))
  done
fi

if [ "$NABORT" -gt 0 ]; then
  echo
  echo "终止详情："
  for c in $CASES; do
    [ "$(case_status "$c")" = "ABORT" ] || continue
    for t in "${AVAILABLE[@]}"; do
      [ "${ST["$c|$t"]}" = "ABORT" ] || continue
      echo "  [$c] $t -> $(tail -1 "$OUT/$c.$t.err" 2>/dev/null | cut -c1-100)"
    done
  done
fi

if [ "$MODE" = "update" ]; then
  {
    echo "# 源码探针基线：每行「case 状态」。"
    echo "# 状态语义：PASS = 各后端逐字节一致；DIVERGENT = 存在跨后端差异；ABORT = 某后端在途中终止。"
    echo "# 后端集合: ${AVAILABLE[*]}"
    echo "# 改动此文件必须说明理由：静默放宽基线等于掩盖差异。"
    for c in $CASES; do
      printf '%-28s %s\n' "$c" "$(case_status "$c")"
    done
  } > "$BASELINE"
  echo
  echo "已写入基线: $BASELINE（后端: ${AVAILABLE[*]}）"
  exit 0
fi

if [ "$MODE" = "check" ]; then
  if [ ! -f "$BASELINE" ]; then
    echo "缺少基线文件 $BASELINE，先跑 --update 并说明理由。" >&2
    exit 4
  fi
  cur="$OUT/current-baseline.txt"
  : > "$cur"
  for c in $CASES; do
    printf '%-28s %s\n' "$c" "$(case_status "$c")" >> "$cur"
  done
  if diff -q <(grep -v '^#' "$BASELINE") "$cur" > /dev/null; then
    echo
    echo "基线一致（$BASELINE）"
    exit 0
  fi
  echo
  echo "FAIL：源码探针状态与基线不符" >&2
  diff -u <(grep -v '^#' "$BASELINE") "$cur" | sed -n '3,40p' | sed 's/^/  /' >&2
  echo "  若是新增的可解释差异，更新基线并在提交信息里说明理由。" >&2
  exit 1
fi

# 报告模式：有 DIVERGENT/ABORT 时返回 1，方便人工判断
if [ "$NDIV" -gt 0 ] || [ "$NABORT" -gt 0 ]; then
  exit 1
fi
exit 0
