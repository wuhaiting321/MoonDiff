#!/usr/bin/env bash
# 四后端覆盖普查：证明第四个后端真的参与了差分，而不是被跳过。
#
# 单独成脚本的理由是踩过坑：这段逻辑原先内联在 workflow 里，且用
# `out=$(bash scripts/matrix.sh ...)` 捕获输出——一旦 matrix.sh 提前失败，
# 错误信息会连同退出码一起被吞掉，日志里只剩「零输出 + 退出码 2」。
# 现在一律 tee 到日志，任何失败都带着上下文。
#
# 用的就是 matrix.sh 本身：如果某个后端在这里不可用，矩阵会少一行并打印
# unavailable，本脚本据此判定「四后端主张不成立」。

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

MOON="${MOON:-moon}"
BACKENDS=(wasm wasm-gc js native)
PROBES=(
  frem-zero fdiv-zero nan-arith cast-edge
  i64-overflow int-overflow str-unicode subnormal
)

mkdir -p ci-out

fail=0
for n in "${PROBES[@]}"; do
  file="ci-out/census-$n.txt"
  bash scripts/matrix.sh "probe:$n" "${BACKENDS[@]}" 2>&1 | tee "$file"
  rc=${PIPESTATUS[0]}
  if [ "$rc" -ne 0 ]; then
    echo "  [warn] matrix.sh 退出码 $rc（探针触发 trap 时属预期）"
  fi

  if grep -q 'unavailable' "$file"; then
    echo "  [FAIL] probe:$n —— 有后端未运行，四后端主张不成立"
    fail=1
  fi

  rows=$(grep -cE '^\| *(wasm|wasm-gc|js|native) +\|' "$file" || true)
  rows=${rows:-0}
  if [ "$rows" -ne 4 ]; then
    echo "  [FAIL] probe:$n —— 矩阵 $rows 行，应为 4 行"
    fail=1
  fi
  echo
done

if [ "$fail" -eq 0 ]; then
  echo "四后端覆盖普查通过：${#PROBES[@]} 个探针均在 wasm / wasm-gc / js / native 上完成比较"
else
  echo "四后端覆盖普查失败：见上方 [FAIL] 行" >&2
fi
exit "$fail"
