# 上游 issue 草稿：`INT_MIN / -1` 在 wasm 与 wasm-gc 上终止进程

本文件是提交给 `moonbitlang/core` 的 issue 正文草稿。正文已按「实测输出 + 可核查依据 +
明确留出反证空间」写，不含推测性结论。发布前请先看下面的操作说明。

## 发布前须知（中文）

1. **用你自己的账号发**：<https://github.com/moonbitlang/core/issues/new>，
   标题用下面「Title」一行的原文。
2. **先补一条 native 结果**（可选但推荐）。本机是 Windows，缺 MSVC Build Tools，
   `native` 没跑。若手边有 Linux/macOS 机器或 WSL，把
   `moon run main --target native` 的输出补进 Environment 一节即可，其余内容不要改。
3. **正文里的输出来自实测**，不要改数字、步号或错误文本；唯一的改动是本机绝对路径
   用 `<repo>` 代替（`wasm-gc` 的调用栈会打印源码路径）。如果换工具链版本复现，
   请把版本号一并改掉，并在正文里说明。
4. **若上游回复「trap 是有意设计」**，不要争辩。正确做法是把 `docs/FINDINGS.md` 里这条的
   裁定从 `SPEC-VIOLATION` 改为 `UNDETERMINED`，把回复链接记在「依据」里，
   并说明「本工具不代替上游定义语义」。裁定的价值在于可被证据推翻，不在于永远正确。
5. 这条 issue 的目标是**让语义变明确**（写进文档或对齐后端），不是要求对方立刻改实现。

---

## Title

```
[wasm/wasm-gc] Int and Int64 division overflow (min_value / -1) aborts instead of wrapping
```

## Body

### Summary

On the `wasm` and `wasm-gc` backends, integer division overflow aborts the program:

```
RuntimeError: divide result unrepresentable
```

On `js`, the same expression evaluates to `-2147483648` and execution continues normally.
The same divergence exists for `Int64`.

`moonbitlang/core` documents `Int` as a 32-bit two's-complement type whose operations wrap
around on overflow, so the two wasm backends appear to diverge from that documented behaviour.
If trapping is the intended semantics instead, then the behaviour is currently undocumented
and inconsistent across backends — either way it would be worth pinning down.

### Environment

- `moon 0.1.20261020 (2284bd2 2026-10-20)`
- `moonc v0.10.16+b1a0e846e (2026-10-16)`
- `moonbitlang/core 0.10.16`
- Windows 11 (10.0.26100), x86_64
- Node.js v22.22.2
- Backends tested: `wasm`, `wasm-gc`, `js`
  (`native` was not run locally — this machine has no MSVC Build Tools)

### Minimal reproduction

No dependencies, 7 lines:

```moonbit
fn main {
  let a : Int = -2147483648
  let b : Int = -1
  println("before")
  println(a / b)
  println("after")
}
```

`moon run main --target wasm`:

```
before
RuntimeError: divide result unrepresentable
    at __moonbit_main
```

`moon run main --target wasm-gc`:

```
before
RuntimeError: divide result unrepresentable
    at __moonbit_main <repo>/main/main.mbt:5
```

In both cases `after` is never printed and the process exits with code 1:
the abort kills the whole program, it is not a catchable error value.

`moon run main --target js`:

```
before
-2147483648
after
```

It is not a constant-folding artifact. Taking the divisor from `@env.args()` at runtime
gives the same result on all three backends:

```moonbit
// moon.pkg: import { "moonbitlang/core/env" }
fn main {
  let args = @env.args()
  let b : Int = if args.length() > 0 { -1 } else { 1 }
  let a : Int = -2147483648
  println("before")
  println(a / b)
  println("after")
}
```

The same holds for `Int64` (`-9223372036854775807L - 1L` divided by `-1L`):
`wasm` / `wasm-gc` raise the same `RuntimeError`, `js` returns `-9223372036854775808`.

### What the documentation currently says

From `core/builtin/intrinsics.mbt`:

- `Add for Int32`: "Performs two's complement arithmetic, which means the operation will
  wrap around if the result exceeds the range of a 32-bit integer." The doc example is
  `2147483647 + 1 == -2147483648`.
- `Div for Int32`: documents truncation towards zero and "Throws a panic if `divisor` is zero".
  It does not say what happens when the quotient itself is not representable.

So the wrapping rule is stated for arithmetic in general and demonstrated for addition,
but the division doc comment only covers the divisor-is-zero case.

### Expected behaviour

If integer division follows the same wrapping rule as the rest of the fixed-width arithmetic,
then `Int::min_value / -1` should be `Int::min_value`, and `Int64::min_value / -1` should be
`Int64::min_value` — which is what the `js` backend already does.

If trapping is intentional, it would help to:

1. document it on `Div for Int32` / `Div for Int64` (the current doc only mentions division
   by zero), and
2. decide what `js` should do, since it currently wraps silently.

### How this was found

This came out of a cross-backend differential harness I maintain,
[MoonDiff](https://github.com/wuhaiting321/MoonDiff), which runs the same primitive operations
on all four backends and compares the results bit-for-bit. The three-instruction program is
checked in as `examples/min-div-overflow.json`.

I am happy to run extra probes, test `native` on Linux, or narrow this down further if that
would help.
