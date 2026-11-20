# 案例

本文件先用**一次完整运行**说明机制怎么跑，再用**四个具体案例**说明它产出什么。
每个案例统一六个字段：**对象 / 输入 / 原始输出 / 裁定 / 条款出处 / 边界**。

---

## 先看一次完整运行

一条命令 `bash scripts/matrix.sh examples/min-div-overflow.json`，输出分三段：

```
MoonDiff 一致性矩阵
  后端数量 : 3
  转录步数 : 0 / 0 / 4
  判定     : ABORTED（有后端在途中终止，见 note 列）

+--------------+----------+--------+------------------------------------+
| backend      | status   | step   | note                               |
+--------------+----------+--------+------------------------------------+
| wasm         | ABORT    | ?      | 无结束哨兵：trap/abort，转录可能被丢弃 |
| wasm-gc      | ABORT    | ?      | 无结束哨兵：trap/abort，转录可能被丢弃 |
| js           | PASS     | -      | baseline                           |
+--------------+----------+--------+------------------------------------+

注意：存在终止性差异（ABORT）。这类差异不会体现为某一步的取值不同，
      而是某个后端在途中直接终止；用 scripts/localize.py 可以二分出确切步号。

裁定
  结论   : 无条款不一致（Verdict: UNSPECIFIED-DIVERGENCE）
  议题   : 整数除法/取模的商（余数）不可表示：min_value / -1
  分歧   : wasm=ABORT, wasm-gc=ABORT, js=i-2147483648
  缺口   : 该条目全文只规定「除数为 0 时 panic」，
           未规定商不可表示（min_value / -1）时应回绕还是终止。
           回绕一侧与四条算术运算的定宽二补数语义一致，
           终止一侧与硬件除法异常一致，两者都能自圆其说；本工具只报事实，
           不替规范下判断。
  依据   : builtin/intrinsics.mbt:298-309
  原文   : "Throws a panic if `divisor` is zero."
```

**第一段是矩阵**：谁和谁不一样。`ABORT` 表示该后端在途中终止、转录里没有结束哨兵；
`step` 显示 `?` 是因为转录被丢弃、步号不可信；`native` 显示 `unavailable`
是因为本机缺 MSVC，不是失败——换一台有 MSVC 或 gcc 的机器，这一列会自己出现。

**第二段是归因**：终止性差异被单独识别。它不是「第 N 步取值不同」，
而是「某个后端根本走不到第 N 步」——这两件事的排查方式完全不同，
混在一起会得出错误结论。

**第三段是裁定**：结论、分歧、缺口、依据、原文五样齐给。依据指向
`builtin/intrinsics.mbt:298-309`，原文只引涉及异常的那一句——引多了反而模糊。

三段都不是生成的套话：矩阵来自四次真实执行的退出码与 stdout，
裁定里的依据可以打开文件逐字对照，任何一台装了工具链的机器都能重跑出同样的输出。

---

## 四个案例

四个案例刻意选了四种结论——三个有差异，一个没有：

| 案例 | 对象 | 结论 | 说明什么 |
| --- | --- | --- | --- |
| A | `BigInt` 大数乘法 | 无差异 | 工具能查真实库；这次查出来是一致的 |
| B | `INT_MIN / -1` | `UNSPECIFIED-DIVERGENCE` | 有差异，但规范没写，不指认违规方 |
| C | 常量折叠后的 NaN 符号位 | `IMPLEMENTATION-FREEDOM` | 有差异，规范明文允许，不是缺陷 |
| D | `String` 长度语义 | 四后端一致 | 一致但**不等于**正确，工具判不了 |

四档裁定只在**出现差异**时使用。案例 A 没有差异，因此不进任何一档——这一点必须说清楚，
否则「四档」会变成一个什么都能装的筐。

所有数字都是实测输出，未做任何修饰；复现命令在每节末尾。

---

## 案例 A：`BigInt` 大数乘法（无差异）

**对象**：`moonbitlang/core` 的 `bigint` 包，`BigInt` 的乘法与十进制渲染。

**输入**：

```
123456789012345678901234567890 * -987654321098765432109876543210
```

两个操作数都是 30 位十进制数，乘积 60 位，远超 `Int64`（约 19 位）与 `UInt64` 的表示能力。
这个 case 挑的是大数库最容易出错的地方：多字长进位与符号处理。

**原始输出**（`for t in wasm wasm-gc js; do moon run probes --target $t -- bigint-mul; done`）：

```
bigint-mul = -121932631137021795226185032733622923332237463801111263526900
```

四个后端逐字节相同。本机实测 `wasm` / `wasm-gc` / `js` 三列一致，
`native` 列在 CI（Linux runner）上同为上述值。

**裁定**：无差异，不适用四档。

**条款出处**：不需要。裁定的前提是「存在差异」，无差异时谈不上谁对谁错。
乘积的十进制表示可以脱离任何实现独立核对（任意高精度计算器，或手算分段卷积），
因此这条结论不依赖被测系统自证。

**边界**：

- 只测了**这一对**操作数。60 位结果正确不证明 6000 位结果正确，
  也不证明负号、前导零、`to_string` 的进制参数在别的输入上一致。
- 这条案例的价值是**负结果的价值**：它证明工具在真实库上能跑通、能比对、能给出一致结论，
  而不是只会在自己构造的探针上找差异。它不构成「BigInt 正确」的证据。

**复现**：

```bash
# 看实际取值：每个后端各打印一行
for t in wasm wasm-gc js; do moon run probes --target $t -- bigint-mul; done
# 看矩阵：该 case 在各后端的状态（缺工具链的列显示 unavailable）
bash scripts/source-probe.sh bigint-mul
```

---

## 案例 B：`-2147483648 / -1`（无条款不一致）

**对象**：`Int` 的整数除法，`moonbitlang/core` 的 `Div for Int32`。

**输入**：规格程序，3 条指令（伪代码渲染，实际是 `examples/min-div-overflow.json` 里的单行 JSON）：

```
iset r0 -2147483648      # INT_MIN
iset r1 -1
idiv r2 r0 r1            # r2 = INT_MIN / -1
```

**原始输出**（`bash scripts/matrix.sh examples/min-div-overflow.json`，矩阵部分）：

```
+--------------+----------+--------+------------------------------------+
| backend      | status   | step   | note                               |
+--------------+----------+--------+------------------------------------+
| wasm         | ABORT    | ?      | 无结束哨兵：trap/abort，转录可能被丢弃 |
| wasm-gc      | ABORT    | ?      | 无结束哨兵：trap/abort，转录可能被丢弃 |
| js           | PASS     | -      | baseline                           |
+--------------+----------+--------+------------------------------------+

裁定
  结论   : 无条款不一致（Verdict: UNSPECIFIED-DIVERGENCE）
```

两点说明。**`step` 显示 `?` 而不是 `0`**：trap 会连已打印的转录一起丢弃，
步号不可信，此时精确步号由 `scripts/localize.py` 前缀二分给出——宁可显示「不知道」，
也不显示一个错误的确定值。**本机 `native` 列显示 `unavailable`**（缺 MSVC），
CI 的 Linux runner 上它是 `ABORT`，与 wasm 相同；存活方 js 的取值是 `i-2147483648`。

**裁定**：`UNSPECIFIED-DIVERGENCE`——只报不一致，不指认违规方。

三份输出不同是可复现的事实；而规范对「商不可表示」这一情形没有规定，
因此任何一方都不能被判为违规。

**条款出处**：`core/builtin/intrinsics.mbt:298-309`（`Div for Int32`）。

原文只有一句涉及异常：

> "Throws a panic if `divisor` is zero."

同一文件里 `Add`（234-246）、`Sub`（249-251）、`Mul`（282-283）三条**明文**写了
「按二补数回绕」，而 `Div` 条目对「商本身不可表示」一个字没有。

这个缺口是有意义的，因为两侧都能自圆其说：回绕一侧与四条算术运算的定宽二补数语义一致，
终止一侧与硬件除法异常（x86 `#DE`、wasm `integer divide by zero` 之外的 overflow trap）一致。
**这正是需要上游补一条规定的地方，而不是本工具替它选一边。**

**边界**：

- 只覆盖「被除数为 `INT_MIN`、除数为 `-1`」这一格。除数为 `0` 不在内——
  规格程序里整数除零被显式定义为 `0`（见 `docs/SCOPE.md` 不覆盖第 4 条），
  为的是让差异可观察而不是让进程死掉。
- `Int64` 的同一情形**同样复现**（`-9223372036854775808 / -1`），但本案例只展示 `Int32`，
  免得把两件事混在一起。
- 若上游确认 trap 是有意设计，本条应改判为 `UNDETERMINED` 并附上回复链接。

**复现**：

```bash
bash scripts/matrix.sh examples/min-div-overflow.json
bash scripts/shrink.sh examples/min-div-overflow.json    # 收缩并复跑，输出 verified: reproduce
```

---

## 案例 C：常量折叠后的 NaN 符号位（实现自由度）

**对象**：`Double` 的 `0.0 / 0.0` 在**编译期常量折叠**路径上的结果。

**输入**（探针源码原文，`probes/cases_double.mbt`）：

```moonbit
fn case_double_nan_literal() -> Unit {
  emit("double-nan-literal", hex16((0.0 / 0.0).reinterpret_as_int64()))
}
```

`0.0 / 0.0` 是编译期常量，会被常量折叠成一个固定的 NaN；`reinterpret_as_int64`
拿到它的位模式，`hex16` 渲染成 16 位十六进制。**比的是位模式，不是文本**——
文本形式的 `NaN` 在四个后端上完全一样，看不出任何差异。

**原始输出**（`for t in wasm wasm-gc js; do moon run probes --target $t -- double-nan-literal; done`）：

```
wasm     double-nan-literal = fff8000000000000
wasm-gc  double-nan-literal = fff8000000000000
native   double-nan-literal = fff8000000000000   （CI Linux runner 实测）
js       double-nan-literal = 7ff8000000000000
```

这是 64 位位模式的十六进制写法（探针原样打印，不带 `0x` 前缀）。
`fff8` 开头是**负** quiet NaN，`7ff8` 开头是**正** quiet NaN，两者指数位全 1、
尾数最高位为 1，都属于合法的 quiet NaN。

**裁定**：`IMPLEMENTATION-FREEDOM`——不是缺陷。

**条款出处**：

- IEEE 754-2019 §6.2.3：NaN 的符号位不在标准的规定范围内，正负 quiet NaN 都是合法结果；
- WebAssembly 规范 *NaN propagation* 一节明文写明结果 NaN 的符号位 **non-deterministic**。

条款不是「没写」，而是**写明由实现自选**——这是它与案例 B 的根本区别：
B 是规范缺了一格，C 是规范把这一格留空并说「随你」。

**边界**：

- 差异只在**常量折叠**路径上出现。同一表达式在运行期计算（`double-nan-runtime`）时四后端一致——
  这说明它是「编译路径不同」而不是「后端语义不同」，两者处置方式完全不同：
  前者应当在编译器里归一化，后者才需要怀疑后端。
- 它仍然值得记录，理由是工程性的：依赖位序列化的代码（哈希、缓存键、黄金文件比对）
  会因为编译期常量折叠而出现平台相关行为，应当显式归一化 NaN 的载荷与符号。
- 把这一条报成 bug 是差分工具最常见的过度断言。本项目在 `semantic` 比较档里折叠掉它。

**复现**：

```bash
# 看取值（矩阵里该 case 显示 DIVERGENT，但要看具体值要用下面这条）
for t in wasm wasm-gc js; do moon run probes --target $t -- double-nan-literal; done
# 常量折叠路径的独立复现（不经过探针，用另一条代码路径交叉验证）
for t in wasm wasm-gc js; do moon run cmd/driver --target $t -- literals | head -1; done
```

---

## 补充：一个「一致但不正确」的例子

上面三个案例都是「差异」或「无差异」。还有第三类值得记下来：**四个后端完全一致，
但结果本身是个陷阱**。

对象是 `String` 的长度语义。输入 `"a😀中"`（一个 ASCII、一个 BMP 外字符、一个 BMP 汉字）：

```
string-length = 4 3
```

（`for t in wasm wasm-gc js; do moon run probes --target $t -- string-length; done`）

两个数字分别是：

- `s.length()` → **4**（UTF-16 码元数；😀 占两个码元）
- `s.to_array().length()` → **3**（码点数）

还没完：切片 `s[1:3]` 是**按码元**索引的。在 `"a😀中b"` 上执行它，
实测打印 `[1] 128512`——1 个字符、码点 `0x1F600`，也就是只取到了 😀，
而不是「😀中」。三个口径里**两个按码元、一个按码点**，混用就会切到半个代理对。

关键在于：这类错误在四个后端上表现**完全一致**，`moon test` 不会报，
本工具也判不了它——它只能说明「四个后端算的是同一个东西」。

**这不是 bug，是 API 设计陷阱**，因此不进四档的任何一档：
规范没有规定「长度必须只有一个口径」，没有条款可以对照，也就谈不上谁违反。

它被记下来的理由，恰好是要说清这个工具的边界：**一致不等于正确**。
MoonDiff 只能回答「四个后端算的是不是同一个东西」，回答不了「这个东西是不是你想要的」。
把它当成后者来用，就会得出错误结论。

**复现**：

```bash
# 三个后端各打印一行，应当都是 4 3
for t in wasm wasm-gc js; do moon run probes --target $t -- string-length; done
# 切片按码元的实证：对 "a😀中b" 打印 [1] 128512（只取到 😀 一个字符）
for t in wasm wasm-gc js; do moon run probes --target $t -- string-substring; done
# 矩阵里这两行都应当是 PASS（三个后端一致）
bash scripts/source-probe.sh string-length
```

---

## 三个案例共同说明的事

| 读者可能的问题 | 这三个案例的回答 |
| --- | --- |
| 工具真的能查真实库吗？ | 案例 A 查了 `BigInt`，跑通了，给出一致结论 |
| 查出差异之后呢？ | 案例 B 定位到 3 条指令，收缩后复跑仍复现 |
| 是不是所有差异都被说成 bug？ | 案例 C 判为自由度；案例 B 只报不一致不指认违规方 |
| 一致就等于正确吗？ | 补充案例说明不等——这是工具的边界，写在 `docs/SCOPE.md` |

全部结论都能用仓库里的命令复跑，不需要网络、不需要额外依赖。
