#!/usr/bin/env bash
# 收缩 + 复跑验证。
#
# 用法：
#   scripts/shrink.sh examples/min-div-overflow.json        # 自动定位目标步
#   scripts/shrink.sh probe:int-overflow 0                  # 指定步号
#
# 做的事（四步，一步不少）：
#   1. 原程序交给可用后端跑一遍，收下四份现场；
#   2. 收缩到分歧依赖锥，拿到更小的程序；
#   3. **把收缩后的程序再交给同一批后端跑一遍**——这就是「复跑」；
#   4. 两份现场比对，末行输出 `verified: reproduce` 或 `NOT-REPRODUCED`。
#
# 退出码：0 = 复现成功；1 = 未复现；2/3/4 = 用法或环境问题。
# 未复现不等于脚本坏了：它意味着收缩改变了行为的观察结果，
# 而这正是必须被看见、而不是被一句「收缩是语义空操作」盖过去的情况。

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

MOON="${MOON:-moon}"
OUT=".moondiff-out/shrink"
mkdir -p "$OUT"

usage() {
  echo "用法: scripts/shrink.sh <probe:名字 | 程序JSON | 文件路径> [步号|auto]" >&2
  exit 2
}

ARG="${1:-}"
[ -z "$ARG" ] && usage
STEP="${2:-auto}"

case "$ARG" in
  probe:*)
    NAME="${ARG#probe:}"
    PROG=$($MOON run cmd/moondiff --target wasm -- probe "$NAME" 2>/dev/null | tail -1)
    LABEL="probe:$NAME"
    ;;
  "{"*)
    PROG="$ARG"
    LABEL="inline"
    ;;
  *)
    if [ -f "$ARG" ]; then
      PROG=$(tr -d '\r\n' < "$ARG")
      LABEL="$ARG"
    else
      usage
    fi
    ;;
esac

if [ -z "${PROG:-}" ] || [ "${PROG:0:1}" != "{" ]; then
  echo "错误：无法解析程序输入" >&2
  exit 3
fi

# 后端可用性：与 matrix.sh 用同一个探针（常量折叠电池），口径一致。
AVAILABLE=()
for t in wasm wasm-gc js native; do
  printf '  探测后端 %-8s ... ' "$t"
  if $MOON run cmd/driver --target "$t" -- literals > "$OUT/lit-$t.txt" 2> "$OUT/lit-$t.err"; then
    AVAILABLE+=("$t")
    echo "ok"
  else
    echo "unavailable（已跳过）"
  fi
done
echo

if [ ${#AVAILABLE[@]} -lt 2 ]; then
  echo "错误：可用后端不足 2 个（${AVAILABLE[*]:-无}），无法做差分。" >&2
  exit 4
fi

# 同一批后端、两套输出文件：orig-<t>.txt 与 new-<t>.txt。
run_orig() {
  ORIG_ARGS=()
  for t in "${AVAILABLE[@]}"; do
    $MOON run cmd/driver --target "$t" -- "$PROG" > "$OUT/orig-$t.txt" 2> "$OUT/orig-$t.err"
    ORIG_ARGS+=("$t=$(cat "$OUT/orig-$t.txt")")
  done
}

run_new() {
  NEW_ARGS=()
  for t in "${AVAILABLE[@]}"; do
    $MOON run cmd/driver --target "$t" -- "$SHRUNK" > "$OUT/new-$t.txt" 2> "$OUT/new-$t.err"
    NEW_ARGS+=("$t=$(cat "$OUT/new-$t.txt")")
  done
}

echo "== 1/4 原始执行 =="
echo "输入   : $LABEL"
run_orig
echo "  后端   : ${AVAILABLE[*]}"
echo

echo "== 2/4 收缩 =="
SHRINK_OUT=$($MOON run cmd/moondiff --target "${AVAILABLE[0]}" -- shrink "$PROG" "$STEP" "${ORIG_ARGS[@]}")
printf '%s\n' "$SHRINK_OUT"
SHRUNK=$(printf '%s\n' "$SHRINK_OUT" | tail -1)
if [ "${SHRUNK:0:1}" != "{" ]; then
  echo "错误：没能从收缩输出里取出程序 JSON" >&2
  exit 3
fi
echo

echo "== 3/4 收缩后复跑（同一批后端） =="
run_new
echo "  后端   : ${AVAILABLE[*]}（与第 1 步相同）"
echo

echo "== 4/4 现场比对 =="
VERIFY_OUT=$($MOON run cmd/moondiff --target "${AVAILABLE[0]}" -- verify "${ORIG_ARGS[@]}" -- "${NEW_ARGS[@]}")
printf '%s\n' "$VERIFY_OUT"

printf '%s\n' "$VERIFY_OUT" | grep -q '^验证结果 : verified: reproduce$'
