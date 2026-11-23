# 测试方法

## 六层检验

| 层 | 命令 | 验证什么 |
| --- | --- | --- |
| 单元测试 | `moon test` | 编码、编解码往返、解释器确定性、随机源确定性、依赖闭包、裁定边界 |
| 跨后端测试 | `moon test --target wasm-gc` / `--target js` / `--target native` | 同一批断言在其余后端上同样通过 |
| **工具自举** | `bash scripts/selfcheck.sh` | `stats`/`matrix`/`shrink`/`gen` 在四个后端上输出**逐字节一致** |
| **回归基线** | `bash scripts/regress.sh` | 11 项判定的标签与 `tests/expected.txt` 一致，只对新增差异报警 |
| 探针矩阵 | `bash scripts/matrix.sh probe:<名字>` | 8 组固定边界探针的跨后端一致性 + 规范裁定 |
| **收缩后复跑** | `bash scripts/shrink.sh <输入>` | 最小反例重跑后仍复现同一分歧（`verified: reproduce`） |
| **覆盖边界** | `bash scripts/coverage.sh --check` | 接口触达清单逐条可核对，README 数字与现算结果逐字一致 |
| **源码探针** | `bash scripts/source-probe.sh --check` | 30 个普通 MoonBit 探针在四后端逐字节一致，基线不漂移 |
| 案例文档 | `docs/CASES.md` 里每条的复现命令 | 文档里贴的输出与命令都实跑过，跑不出来即文档错误 |
| 常量折叠电池 | `moon run cmd/driver --target <t> -- literals` | 24 条编译期表达式的跨后端位模式 |

后三层是「守则」的落地：自举证明工具自身可信，基线证明差异不被掩盖，
矩阵证明结论可复现。

### 基线为什么要声明后端集合

判定标签是**后端集合的函数**：多一个后端，违规方名单会变，
`PASS` 也可能翻成 `FREEDOM`。所以 `tests/expected.txt` 第二行显式写着
`# backends: wasm wasm-gc js`——它记录的是「在这组后端上观察到的事实」。

`scripts/regress.sh` 复现时只跑这一组，集合不符会直接报错退出（退出码 6），
而不是拿 A 组的基线去判 B 组的结果。这不是回避 `native`：`native` 的参与由
CI 的 *Four-backend coverage census* 单独断言（每个探针的矩阵必须出现 4 行，
且不得出现 `unavailable`），常量折叠电池也逐后端断言 24 条。
基线管「已知结论不被悄悄改动」，census 管「第四个后端真的在跑」，两件事分开证明。

## 当前状态

```
Total tests: 62, passed: 62, failed: 0
```

后端覆盖：本机 `wasm` / `wasm-gc` / `js`；`native` 由 CI（`ubuntu-latest`）覆盖，
CI 中显式断言 native 产出完整的 24 条折叠结果，避免「未运行也算通过」。

### CI 实测结果（2026-11-23，run #18，提交 fb2ac03）

四个后端**全部真实执行**，不是挑选后的结果：

```
unit tests / wasm        check + build + test  62 tests, 62 passed
unit tests / wasm-gc     check + build + test  62 tests, 62 passed
unit tests / js          check + build + test  62 tests, 62 passed
unit tests / native      check + build + test  62 tests, 62 passed

自检通过：stats / matrix / shrink / gen 在 wasm wasm-gc js native 上输出逐字节一致
回归通过：11 项判定与基线一致（后端: wasm wasm-gc js）
四后端覆盖普查通过：8 个探针均在 wasm / wasm-gc / js / native 上完成比较
折叠电池：wasm 24 / wasm-gc 24 / js 24 / native 24
收缩复跑：verified: reproduce（反例 NOT-REPRODUCED 被拒）
```

> 顺带记录一个真实教训：CI 首次运行失败在 census 一步，日志只有「零输出 + 退出码 2」。
> 根因是 `scripts/matrix.sh` 曾以 CRLF 入库，Linux 上 bash 读它直接语法错误，
> 而错误信息被 `out=$(...)` 吞掉。Windows 的 Git Bash 容忍 CRLF，本地永远复现不出来。
> 修法是 `.gitattributes` 钉死 `eol=lf`，并把这段逻辑移进脚本改为 `tee` 输出。
> 这类「只在另一个平台上才现形」的故障，正是本项目要对付的东西。

覆盖的断言点（节选）：

- `hex16(-1L) == "ffffffffffffffff"`：位串必须是补码，不能是符号加绝对值
- `escape_str("😀") == "\\u{1f600}"`：增补平面码点必须转义，转录全程 ASCII
- `render_value(VF64(nan), Semantic) == "fnan"`：语义档必须折叠 NaN
- 编解码往返：`Int64` 下界与 NaN 位模式必须无损
- `decode_program` 对损坏输入返回 `None`，不 panic
- 解释器对同一程序两次执行逐行相同
- 整数除零被定义为 0（不 trap，见下文口径说明）
- `f2i` 的饱和语义：`1e30 -> 2147483647`，`NaN -> 0`
- `Rng(12345)` 两次构造给出同一序列；不同种子给出不同序列
- 依赖闭包包含全部前驱、不包含死写入
- `parse_hex16` 与 `hex16` 互为逆运算；长度不足或非法字符返回 `None`
- `nan_sign_only`：正负 quiet NaN 判为真，尾数不同的 NaN 判为假
- `Source` 拒绝空白文档 / 空白定位 / 空白原文 / 含换行的文档名
- `INT_MIN / -1` 裁定为 `UNSPECIFIED-DIVERGENCE:int-div-overflow`，
  分歧列为 `wasm=ABORT`、`js=i-2147483648`，出处 `builtin/intrinsics.mbt:298-309`
- `INT_MIN % -1` 同属 `UNSPECIFIED-DIVERGENCE`
- 加法溢出且某后端不回绕：`SPEC-VIOLATION:int-wrap`，出处 `234-246`
- 减法下溢：出处 `249-251`（条款不同，引用必须跟着换）
- 未溢出的加法（`2147483646 + 1`）不套用回绕条款，落 `UNDETERMINED`
- **终止的后端不被算作更早一步的违规方**（回归：曾把 IMul 那一步判错）
- 正负 NaN 差异裁定为 `FREEDOM:nan-sign`，出处为 wasm 规范的 `NaN propagation`
- 仅文本写法不同裁定为 `UNSPECIFIED-DIVERGENCE:float-format`，
  出处 `builtin/double.mbt:274-296`
- 裁定文本同时含定位（`文件:行号`）与原文
- `find_static_site` 能在程序深处（第 5 步）定位溢出点，也认得乘法溢出
- 收缩后复跑：五项特征（后端集合、终止集合、分歧形态、分歧原语、两侧取值）
  逐项有单测，任一项变化都被判成 `NOT-REPRODUCED` 并说明是哪一项
- **转录截断不被算成取值分歧**：某后端 trap 后转录为空，朴素按行比对会报
  「第 0 步取值不同」，实际那是长度差异，不是任何指令算出来的值
- 步号重排不影响判定（收缩会删掉目标步之前的支线，步号必然变）

## 收缩之后为什么还要复跑

收缩的正确性是可以静态论证的：直线程序里删掉不参与分歧的指令，
保留指令读到的值一个字节都不会变。但**论证不等于证据**——
闭包漏一个前驱、直线假设哪天不成立，这句论证就变成没人能检查的承诺。

所以 `scripts/shrink.sh` 在收缩后会真的再跑一次，比较两份现场：

| 比较项 | 不等时说明什么 |
| --- | --- |
| 后端数量 | 复跑没交给同一批后端，验证本身失效 |
| 终止集合 | 收缩改变了谁 trap，收缩不是语义空操作 |
| 分歧形态 | 从「终止 + 取值分歧」退化成「只有终止」，或反过来 |
| 分歧原语 | 分歧点漂移了，收缩删掉了不该删的指令 |
| 两侧取值 | 同一条指令、同样操作数却算出不同值，说明输入被改动了 |

末行固定输出 `verified: reproduce` 或 `NOT-REPRODUCED`，两者都是字面量，
CI 用 `grep -q` 精确匹配。CI 里还跑一个反例：把目标步钉在 0，
trap 会被收缩掉，此时必须判 `NOT-REPRODUCED` 并失败——
没有这个反例，`verified` 本身也可能只是一句常量。

这一步在开发时立刻抓到过一个真 bug：自动定位取的是「第一个静态候选」，
而 `int-overflow` 里先有乘法溢出、后面才是除法终止，收缩到乘法那一步再跑，
trap 就消失了。改成「取裁定所指的指令」后才复现。
**验证机制的第一次运行就否证了它要验证的东西**，这正是它该有的样子。

## 覆盖率为什么不是手写的

`README.md` 里那一行「接口触达：24 / 215 = 11.2%」是 `scripts/coverage.sh` 的输出，
而且 `--check` 会把它跟现算结果逐字比对，不一致就退出 1。手写常量的路被堵死了。

分母：被测类型的 `.mbti` 里 `pub fn` 的行数（`builtin` 只计
`String`/`Double`/`Char`/`BytesView` 的方法）。
分子：`probes/api-touch.txt` 的登记，逐条过四道校验：

1. 接口确实在该包的 `.mbti` 里（不能编接口）；
2. 符号名字确实出现在探针源码里（不能登记没调过的东西）；
3. 用例名确实在 `probes -- list` 里（不能登记不存在的 case）；
4. 符号出现在**这条用例自己的函数体**里（`via:` 时是其辅助函数体），
   不能拿别的 case 的调用充数。

三个负例都实测过，都能让脚本退出 1：

| 负例 | 脚本报的错 |
| --- | --- |
| 编一个不存在的接口 `BigInt::frobnicate` | 不在 `.mbti` / 源码里没调用 / 不在函数体里（三连报） |
| 把 `String::get_char` 登记到 `string-cjk` | 不在 `case_string_cjk` 的函数体里 |
| 把 `String::length` 登记到 `string-nope` | 用例不存在 + 函数体对不上 |

把 README 的百分比改一个数字，`--check` 同样退出 1 并打印两边的内容。
<!-- 分隔：下面是口径说明，不属于上面的测试层 -->

## 语义口径（本项目显式定义的部分）

差分测试需要一个「什么是正确」的基线。凡是各后端可能自行其是的地方，
本项目在解释器里给出显式定义：

| 情形 | 本项目的口径 | 理由 |
| --- | --- | --- |
| 整数除以 0 | 结果 0，并标记 `special` 分支 | 避免一个后端 trap 掉整个进程，使差异可被观察 |
| 移位量 | 32 位按 31 取模、64 位按 63 取模 | 与主流实现一致，避免未定义 |
| 浮点转整数 | 饱和（`NaN -> 0`，越界取边界） | 让越界转换的差异可观测，而不是直接崩 |
| 字符串长度 | 同时记录码元数（UTF-16）与码点数 | UTF-8/UTF-16 边界是最常见的实现差异 |
| 浮点比较 | 先比位模式，可选再比宿主格式化 | 把「数值不对」与「打印不对」分开归因 |

> 上表是**工具的观测口径**，不是对 MoonBit 语言规范的断言。
> 口径与规范冲突时应以规范为准，并调整本工具。

## 如何新增一个原语

1. `src/spec/program.mbt`：`OpKind` 加构造子；
2. 补 `op_kind_name` / `op_kind_of_name` / `op_kind_arity` / `op_kind_domain`；
3. `src/exec/interp.mbt`：在 `eval_op` 里转发给宿主原语（不要自己实现算术）；
4. `src/gen/gen.mbt`：加入对应 `random_*` 的候选；
5. `src/report/report.mbt`：确认 `op_kind_is_float` 的归类；
6. 补一条单元测试，再跑 `scripts/matrix.sh` 看是否引入新的跨后端差异。

## 如何新增一个探针

在 `cmd/moondiff/probes.mbt` 里给 `probe_names()` 加名字、给 `probe_program()` 加分支，
然后固化成样例：

```bash
moon run cmd/moondiff --target wasm -- probe <名字> > examples/probe-<名字>.json
```
