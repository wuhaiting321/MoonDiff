#!/usr/bin/env python3
"""崩溃点定位：二分找出某个后端最先“崩掉/失去哨兵”的那一步。

背景：wasm/wasm-gc 在遇到 `-2147483648 / -1` 这类溢出除法时会直接 trap，
进程终止，连已经打印的转录都会被丢弃。此时转录长度不能当作“执行到第几步”，
需要重新用前 k 条指令做前缀执行，二分出真正的边界。

用法：
    python scripts/localize.py examples/probe-int-overflow.json
    python scripts/localize.py <程序JSON文本> --backends wasm js

只依赖标准库 + moon 命令，不修改任何项目文件。
"""

import json
import subprocess
import sys
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def run(target: str, ops: list) -> tuple:
    """在指定后端上跑前 len(ops) 条指令，返回 (退出码, 是否出现结束哨兵, 输出行数)。"""
    text = json.dumps({"seed": 0, "profile": "strict", "ops": ops}, ensure_ascii=False, separators=(",", ":"))
    try:
        p = subprocess.run(
            ["moon", "run", "cmd/driver", "--target", target, "--", text],
            cwd=ROOT, capture_output=True, text=True, timeout=180,
        )
    except subprocess.TimeoutExpired:
        return (-1, False, 0)
    out = p.stdout.strip().splitlines()
    ok = bool(out) and out[-1].startswith("#end")
    return (p.returncode, ok, len(out))


def probe(target: str, ops: list) -> bool:
    """该前缀是否“正常完成”。"""
    _, ok, _ = run(target, ops)
    return ok


def main() -> int:
    args = [a for a in sys.argv[1:]]
    backends = ["wasm", "js"]
    if "--backends" in args:
        i = args.index("--backends")
        backends = args[i + 1:]
        args = args[:i]

    if not args:
        print(__doc__)
        return 2

    src = args[0]
    if os.path.exists(src):
        with open(src, "r", encoding="utf-8") as f:
            text = f.read().strip()
    else:
        text = src
    prog = json.loads(text)
    ops = prog["ops"]
    print(f"程序共 {len(ops)} 条指令\n")

    full = {}
    for b in backends:
        code, ok, n = run(b, ops)
        full[b] = ok
        print(f"  {b:8} 退出码={code:<3} 哨兵={'有' if ok else '无'} 输出行数={n}")

    bad = [b for b in backends if not full[b]]
    if not bad:
        print("\n所有后端都正常完成，无崩溃点可定位。")
        return 0
    if len(bad) == len(backends):
        print("\n所有后端都未完成，可能是输入本身损坏。")
        return 1

    good_backend = [b for b in backends if full[b]][0]
    for b in bad:
        lo, hi = 1, len(ops)
        if probe(b, ops[:1]):
            print(f"\n{b}: 单条指令即崩溃，无需二分")
            continue
        # 不变式：probe(lo-1)=True, probe(hi)=False
        while lo < hi:
            mid = (lo + hi) // 2
            if probe(b, ops[:mid]):
                lo = mid + 1
            else:
                hi = mid
        idx = lo - 1
        print(f"\n{b}: 首次崩溃于第 {idx} 步 -> {json.dumps(ops[idx], ensure_ascii=False)}")
        print(f"    对照后端 {good_backend}: {'正常完成' if full[good_backend] else '异常'}")
        if idx > 0:
            print(f"    前缀程序（{idx} 条指令）：")
            print("    " + json.dumps({"seed": 0, "profile": "strict", "ops": ops[:idx]}, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
