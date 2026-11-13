#!/usr/bin/env bash
# 回归基线：已知差异写入 tests/expected.txt，出现「新增差异」时退出码非零。
#
# 这是「不掩盖差异，也不虚报差异」的落地方式：
# 已知的、定性清楚的记在基线里，不再反复报警；
# 新出现的、定性不明的必须让人看见，不许静默通过。
#
# 用法：
#   scripts/regress.sh            # 与基线比对（CI 用这个）
#   scripts/regress.sh --update   # 重新生成基线（人工核对后再提交）

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

MOON="${MOON:-moon}"
OUT=".moondiff-out"
BASE="tests/expected.txt"
mkdir -p "$OUT" tests

UPDATE=0
[ "${1:-}" = "--update" ] && UPDATE=1

# 判定标签是「后端集合」的函数：多一个后端，违规方名单、以及
# PASS / FREEDOM 的归属都可能变。所以基线文件自己声明它是在哪一组
# 后端上录制的，复现时必须用同一组，否则「回归通过」只是一次巧合。
#
# 优先级：环境变量 MOONDIFF_BACKENDS > 基线声明 > 默认四后端。
if [ -n "${MOONDIFF_BACKENDS:-}" ]; then
  read -r -a BACKENDS <<< "$MOONDIFF_BACKENDS"
elif [ "$UPDATE" = "0" ] && [ -f "$BASE" ] && grep -q '^# backends:' "$BASE"; then
  read -r -a BACKENDS <<< "$(grep -m1 '^# backends:' "$BASE" | sed 's/^# backends:[[:space:]]*//')"
else
  BACKENDS=(wasm wasm-gc js native)
fi

AVAILABLE=()
for t in "${BACKENDS[@]}"; do
  if $MOON run cmd/driver --target "$t" -- literals > "$OUT/rg-lit-$t.txt" 2>/dev/null; then
    AVAILABLE+=("$t")
  fi
done
if [ ${#AVAILABLE[@]} -lt 2 ]; then
  echo "可用后端不足 2 个，无法做差分比较。" >&2
  exit 4
fi

if [ "$UPDATE" = "0" ] && [ ${#AVAILABLE[@]} -ne ${#BACKENDS[@]} ]; then
  echo "基线声明的后端集合为 [${BACKENDS[*]}]，当前只有 [${AVAILABLE[*]}] 可用。" >&2
  echo "用不同的后端集合复现同一份基线，结论不可比；" >&2
  echo "请补齐后端，或核对理由后用 --update 重新录制。" >&2
  exit 6
fi

# 判定一个程序在各后端上的一致性结论
judge() {
  local label="$1" prog="$2" args=() t tag
  for t in "${AVAILABLE[@]}"; do
    $MOON run cmd/driver --target "$t" -- "$prog" > "$OUT/rg-$t.txt" 2>/dev/null
    args+=("$t=$(cat "$OUT/rg-$t.txt")")
  done
  tag=$($MOON run cmd/moondiff --target "${AVAILABLE[0]}" -- adjudicate "$prog" "${args[@]}" 2>/dev/null | tail -1)
  printf '%-26s %s\n' "$label" "${tag:-NO-TAG}"
}

NOW="$OUT/regress-now.txt"
{
  for n in frem-zero fdiv-zero nan-arith cast-edge i64-overflow int-overflow str-unicode subnormal; do
    P=$($MOON run cmd/moondiff --target wasm -- probe "$n" 2>/dev/null | tail -1)
    judge "probe:$n" "$P"
  done
  judge "example:min-div-overflow" "$(tr -d '\r\n' < examples/min-div-overflow.json)"
  judge "example:fuzz-seed7" "$(tr -d '\r\n' < examples/fuzz-seed7.json)"
  # 常量折叠电池：wasm 与 js 的差异行数（编译期折叠差异的稳定体现）
  LIT_DIFF=$(diff "$OUT/rg-lit-wasm.txt" "$OUT/rg-lit-js.txt" 2>/dev/null | grep -c '^[<>]')
  printf '%-26s %s\n' "literals:wasm-vs-js" "diff-lines=${LIT_DIFF}"
} > "$NOW"

if [ "$UPDATE" = "1" ]; then
  {
    echo "# MoonDiff 回归基线：每行「反例名 判定标签」。"
    echo "# backends: ${AVAILABLE[*]}"
    echo "# 判定标签含义见 docs/FINDINGS.md；SPEC-VIOLATION = 违反语言规范。"
    echo "# 判定结果取决于后端集合，故上一行显式声明录制时的后端；复现须用同一组。"
    echo "# 改动此文件必须说明理由：静默放宽基线等于掩盖差异。"
    cat "$NOW"
  } > "$BASE"
  echo "已更新基线：$BASE"
  cat "$NOW"
  exit 0
fi

if [ ! -f "$BASE" ]; then
  echo "缺少基线文件 $BASE，请先运行：scripts/regress.sh --update" >&2
  exit 5
fi

if diff <(grep -v '^#' "$BASE") "$NOW" > "$OUT/regress.diff" 2>&1; then
  echo "回归通过：$(wc -l < "$NOW") 项判定与基线一致（后端: ${AVAILABLE[*]}）"
  exit 0
else
  echo "回归失败：出现基线之外的差异。" >&2
  echo "  基线文件：$BASE" >&2
  echo "  差异内容：" >&2
  sed 's/^/    /' "$OUT/regress.diff" >&2
  echo >&2
  echo "  若这是预期内的变化，请说明理由后运行 scripts/regress.sh --update。" >&2
  exit 1
fi
