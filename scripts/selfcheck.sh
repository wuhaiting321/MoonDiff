#!/usr/bin/env bash
# 自检：工具自身在所有后端上必须给出同一份报告。
#
# 这是差分工具最容易犯的错——自己的输出随后端而变，那它给出的
# 「不一致」结论就没有可信度。因此把工具本身也放进矩阵。
#
# 检查四项：stats（统计）、matrix（矩阵+裁定）、shrink（收缩）、gen（生成）。
# 任一项在任意两个后端之间出现字节差异，即判定自检失败。

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

MOON="${MOON:-moon}"
OUT=".moondiff-out"
mkdir -p "$OUT"

BACKENDS=(wasm wasm-gc js native)
AVAILABLE=()
for t in "${BACKENDS[@]}"; do
  if $MOON run cmd/driver --target "$t" -- literals > "$OUT/sc-lit-$t.txt" 2>/dev/null; then
    AVAILABLE+=("$t")
  fi
done
if [ ${#AVAILABLE[@]} -lt 2 ]; then
  echo "可用后端不足 2 个，无法自检。" >&2
  exit 4
fi

PROG=$(tr -d '\r\n' < examples/fuzz-seed7.json)
ARGS=()
for t in "${AVAILABLE[@]}"; do
  $MOON run cmd/driver --target "$t" -- "$PROG" > "$OUT/sc-tr-$t.txt" 2>/dev/null
  ARGS+=("$t=$(cat "$OUT/sc-tr-$t.txt")")
done

for t in "${AVAILABLE[@]}"; do
  $MOON run cmd/moondiff --target "$t" -- stats "$PROG" > "$OUT/sc-stats-$t.txt" 2>/dev/null
  $MOON run cmd/moondiff --target "$t" -- matrix "@$PROG" "${ARGS[@]}" > "$OUT/sc-matrix-$t.txt" 2>/dev/null
  $MOON run cmd/moondiff --target "$t" -- shrink "$PROG" 0 > "$OUT/sc-shrink-$t.txt" 2>/dev/null
  $MOON run cmd/moondiff --target "$t" -- gen 42 24 strict 8 > "$OUT/sc-gen-$t.txt" 2>/dev/null
done

FAIL=0
BASE="${AVAILABLE[0]}"
for kind in stats matrix shrink gen; do
  for t in "${AVAILABLE[@]}"; do
    [ "$t" = "$BASE" ] && continue
    if ! cmp -s "$OUT/sc-$kind-$BASE.txt" "$OUT/sc-$kind-$t.txt"; then
      echo "自检失败：$kind 在 $BASE 与 $t 上输出不同" >&2
      diff "$OUT/sc-$kind-$BASE.txt" "$OUT/sc-$kind-$t.txt" | head -8 | sed 's/^/    /' >&2
      FAIL=1
    fi
  done
done

if [ "$FAIL" -eq 0 ]; then
  echo "自检通过：stats / matrix / shrink / gen 在 ${AVAILABLE[*]} 上输出逐字节一致"
fi
exit "$FAIL"
