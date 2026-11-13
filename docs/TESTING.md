# 测试方法

## 六层检验

| 层 | 命令 | 验证什么 |
| --- | --- | --- |
| 单元测试 | `moon test` | 编码、编解码往返、解释器确定性、随机源确定性、依赖闭包、裁定边界 |
| 跨后端测试 | `moon test --target wasm-gc` / `--target js` / `--target native` | 同一批断言在其余后端上同样通过 |
| **工具自举** | `bash scripts/selfcheck.sh` | `stats`/`matrix`/`shrink`/`gen` 在四个后端上输出**逐字节一致** |
| **回归基线** | `bash scripts/regress.sh` | 11 项判定的标签与 `tests/expected.txt` 一致，只对新增差异报警 |
| 探针矩阵 | `bash scripts/matrix.sh probe:<名字>` | 8 组固定边界探针的跨后端一致性 + 规范裁定 |
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
Total tests: 31, passed: 31, failed: 0
```

后端覆盖：本机 `wasm` / `wasm-gc` / `js`；`native` 由 CI（`ubuntu-latest`）覆盖，
CI 中显式断言 native 产出完整的 24 条折叠结果，避免「未运行也算通过」。

### CI 实测结果（2026-11-13，run #2）

四个后端**全部真实执行**，不是挑选后的结果：

```
unit tests / wasm        Total tests: 31, passed: 31, failed: 0
unit tests / wasm-gc     Total tests: 31, passed: 31, failed: 0
unit tests / js          Total tests: 31, passed: 31, failed: 0
unit tests / native      Total tests: 31, passed: 31, failed: 0

自检通过：stats / matrix / shrink / gen 在 wasm wasm-gc js native 上输出逐字节一致
回归通过：11 项判定与基线一致（后端: wasm wasm-gc js）
四后端覆盖普查通过：8 个探针均在 wasm / wasm-gc / js / native 上完成比较
折叠电池：wasm 24 / wasm-gc 24 / js 24 / native 24
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
- `INT_MIN / -1` 裁定为 `SPEC-VIOLATION`，且违规方只含终止的后端
- `INT_MIN % -1` 的规范值是 `i0`
- 普通除法（如 `-7 / 2`）不触发溢出裁定，落为 `UNDETERMINED`
- 正负 NaN 差异裁定为 `FREEDOM:nan-sign`，不是违规
- 仅格式化文本不同裁定为 `FREEDOM:float-format`
- `find_static_violation` 能在程序深处（第 5 步）定位溢出点

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
