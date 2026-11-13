# 实施步骤

按「先把地基钉死，再往上加能力」的顺序推进，每一步以「可运行、可验证」为完成标准。

## 阶段 0 · 可行性验证（已完成）

- 确认工具链与可用后端：`moon 0.1.20261020`，wasm / wasm-gc / js 可用，native 需 MSVC
- 验证 `@env.args()` 的跨后端差异（js 多出 `node` 与脚本路径）
- 验证浮点位模式、整数溢出、字符串长度的初始分叉点
- 产出：`docs/FINDINGS.md` 的三条观测

## 阶段 1 · 数据地基（已完成）

- `src/core`：`Value`、`hex16`、`escape_str`、三档 `Profile`、`render_value`
- `src/core`：`split_ws`、`first_divergence`、`first_cross_divergence`、`agreement_scores`
- 完成标准：`hex16` 输出补码位串、转录全 ASCII、`moon check` 零错误

## 阶段 2 · 程序模型与编解码（已完成）

- `src/spec/json.mbt`：自带 mini JSON（代理对合并、`\uXXXX` 输出）
- `src/spec/program.mbt`：54 条原语的 `OpKind` 与统一 `Op` 记录
- `src/spec/codec.mbt`：单行 JSON，64 位整数走字符串、浮点走位串
- 完成标准：往返无精度损失；损坏输入返回 `None` 不 panic

## 阶段 3 · 参照解释器（已完成）

- `src/exec`：寄存器读取、54 条原语求值、饱和转换、覆盖边记录
- 完成标准：同程序两次执行逐行相同；除零不 trap

## 阶段 4 · 生成与覆盖引导（已完成）

- `src/gen/rng.mbt`：xorshift64*，与后端无关
- `src/gen/gen.mbt`：常量池、带类型标记的寄存器、按域生成、变异、语料库
- 完成标准：同种子同序列；语料库只收带来新边的输入

## 阶段 5 · 收缩（已完成）

- `src/shrink`：`last_writer`、`reads_of`、`dependency_cone`、`shrink`、伪代码渲染
- 完成标准：闭包含全部前驱、不含死写入；128 条可压到个位数

## 阶段 6 · 报告与 CLI（已完成）

- `src/report`：矩阵、差异摘要、字段级归因、结束哨兵识别
- `cmd/moondiff`：`gen` / `gencorpus` / `run` / `diff` / `matrix` / `shrink` / `stats` / `probe`
- `cmd/driver`：四后端共用执行器 + 24 条常量折叠电池
- 完成标准：矩阵能区分 PASS / FAIL / ABORT 三种判定

## 阶段 7 · 编排与定位（已完成）

- `scripts/matrix.sh`、`scripts/matrix.ps1`：探测可用后端、执行、汇总
- `scripts/localize.py`：对崩溃点做前缀二分
- `examples/`：8 组探针、1 个随机样例、1 个最小 trap 复现

## 阶段 8 · 测试与文档（已完成）

- 20 个单元测试（编码、往返、确定性、闭包）
- `README.md`（申报书）与 `docs/` 五份文档

## 阶段 9 · 规范裁定（已完成）

把结论从「两边不一样」推进到「哪边违反规范」。

- [x] `src/oracle`：三级判定 `Violation` / `Freedom` / `Undetermined`
- [x] `INT_MIN / -1` 的规范值判定（依据 core 文档的回绕语义）
- [x] NaN 符号位的自由度判定（依据 IEEE 754-2019 §6.2.3）
- [x] 浮点格式化的自由度判定
- [x] `find_static_violation`：trap 导致转录丢失时，静态定位真正的溢出点
- [x] `moondiff matrix @<prog>` 与 `moondiff adjudicate` 命令
- 完成标准：`moondiff matrix` 输出末段给出违规方、规范值、依据

## 阶段 10 · 工具自举与回归基线（已完成）

- [x] `scripts/selfcheck.sh`：`stats`/`matrix`/`shrink`/`gen` 在四后端上字节一致
- [x] `scripts/regress.sh`：与 `tests/expected.txt` 比对，只对新增差异报警
- [x] `tests/expected.txt`：11 项已知判定入基线（含 2 项 `SPEC-VIOLATION`）
- [x] trap 时矩阵的 `step` 改显示 `?`，不再误报「第 0 步不同」
- 完成标准：`regress.sh` 退出码 0；新增差异时退出码 1

## 阶段 11 · 四后端 CI（已完成）

- [x] `.github/workflows/ci.yml`：`ubuntu-latest` 上跑满 wasm / wasm-gc / js / native
- [x] 四后端逐 target 跑 `moon test`
- [x] 显式断言 native 真产出 24 条折叠结果（避免「未运行也算通过」）
- [x] 矩阵报告作为 artifact 上传
- 完成标准：CI 中四个 target 全部出现且通过

> 关于本机 `native`：Windows 上 MoonBit 要求 MSVC（`cl.exe` 或 `clang-cl.exe`），
> msys2 的 gcc 不被接受。因此本地矩阵为 3 列并在输出中如实标记；第 4 列由 CI 补齐。
> 这不是回避，而是把「四后端」变成每次提交都被验证的公开事实。

## 阶段 12 · 可自证性（已完成）

- [x] README 「验证方式」三组命令，全部实测可跑
- [x] 删除路线图章节（申报书不需要）
- [x] 文档中的测试数、探针数、后端数与仓库实际一致（31 / 8 / 24 / 3+CI）
- 完成标准：从 clone 到看到裁定，三条命令内完成

## 仍待推进（非本次交付范围）

- 为 3–5 个已发布包生成「生态一致性体检表」，把工具用在真实包上
- 把发现 1 提交上游 issue（复现与分析已就绪，是否上报由作者决定）
- 扩充原语集到 64 位浮点以外的类型（如大整数、Decimal）
