#!/usr/bin/env bash
# MoonDiff 一致性矩阵（bash 版）
#
# 用法：
#   ./scripts/matrix.sh probe:int-overflow        # 内置探针
#   ./scripts/matrix.sh '{"seed":7,...}'          # 直接给程序 JSON
#   ./scripts/matrix.sh prog.json                 # 给文件路径
#
# 设计说明：本脚本只负责“编排”——把同一份程序分别交给四个后端编译执行，
# 再把四份转录交给 moondiff 做判定。工具本体不做进程管理，
# 因此它在任何后端上的行为都是可复现的。

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

MOON="${MOON:-moon}"
OUT=".moondiff-out"
mkdir -p "$OUT"

usage() {
  echo "用法: scripts/matrix.sh <probe:名字 | 程序JSON | 文件路径> [后端...]" >&2
  echo "可用探针:" >&2
  $MOON run cmd/moondiff --target wasm -- probe 2>/dev/null | sed -n '2,$p' | sed 's/^/  /' >&2
  exit 2
}

ARG="${1:-}"
[ -z "$ARG" ] && usage
shift || true
if [ $# -gt 0 ]; then
  BACKENDS=("$@")
else
  BACKENDS=(wasm wasm-gc js native)
fi

# 解析输入
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

echo "== MoonDiff =="
echo "输入   : $LABEL"
echo "指令数 : $(printf '%s' "$PROG" | grep -o '\[' | wc -l)"
echo

AVAILABLE=()
ARGS=()
for t in "${BACKENDS[@]}"; do
  printf '  %-8s ... ' "$t"
  if $MOON run cmd/driver --target "$t" -- literals > "$OUT/lit-$t.txt" 2> "$OUT/lit-$t.err"; then
    AVAILABLE+=("$t")
    echo "ok"
  else
    echo "unavailable（已跳过）"
  fi
done
echo

if [ ${#AVAILABLE[@]} -lt 2 ]; then
  echo "可用的后端不足 2 个，无法做差分比较。" >&2
  exit 4
fi

for t in "${AVAILABLE[@]}"; do
  $MOON run cmd/driver --target "$t" -- "$PROG" > "$OUT/$t.txt" 2> "$OUT/$t.err"
  CODE=$?
  if [ $CODE -ne 0 ]; then
    echo "  注意：$t 退出码 $CODE（可能是 trap，见 $OUT/$t.err）"
  fi
  ARGS+=("$t=$(cat "$OUT/$t.txt")")
done

# 把程序一并交给 matrix：带上它，报告末尾会追加一段规范裁定。
$MOON run cmd/moondiff --target "${AVAILABLE[0]}" -- matrix "@$PROG" "${ARGS[@]}"
