# 原创性排查记录

排查时间：2026-11-12
排查范围：mooncakes.io 包索引与文档页、GitHub 公开仓库、Gitee 公开仓库、往届 MoonBit 赛事公开项目名单。

## 结论

**截至 2026-11-12，在 mooncakes.io / GitHub / Gitee / 往届赛事公开名单等可检索范围内，
未发现与本项目直接重复的实现**——即未发现「针对 MoonBit 多后端做逐位差分验证 + 自动收缩」
的工具或库。

需要说明的是：这不等于「世界上没有人想过这件事」。差分测试本身是成熟方法论
（Csmith、wasm-tools 的 differential fuzzing、C-Reduce 等），
本项目的原创性在于**把它落到 MoonBit 的四后端结构上**，并针对直线程序的特性
重新设计了收缩算法。

## 检索关键词与方法

| 平台 | 关键词 | 结果 |
| --- | --- | --- |
| mooncakes.io | `diff`、`differential`、`fuzz`、`cross-backend`、`conformance` | 有 `quickcheck`（随机测试与收缩），无跨后端比对 |
| mooncakes.io | `wasm`、`component`、`wit` | 有 wasm 运行时与组件模型绑定，无四后端一致性验证 |
| GitHub | `moonbit differential testing`、`moonbit cross backend` | 未发现同类工具 |
| GitHub | `moonbit quickcheck`、`moonbit shrink` | 有单后端的属性测试与收缩 |
| Gitee | `MoonBit 差分`、`MoonBit 多后端` | 未发现同类项目（该平台检索能力有限，仅作辅助参考） |
| 赛事名单 | 历届获奖与入围项目的题目与内容 | 未发现相同方向 |

## 最接近的若干项目，以及本项目的边界

| 项目 | 它做什么 | 本项目不做什么 |
| --- | --- | --- |
| `quickcheck`（mooncakes） | 单后端属性测试，含 `Arbitrary` 与 shrinker | 不做跨后端比对；本项目的收缩对象是「跨后端分歧」而非「属性失败」 |
| `moonbitlang/core` 自带测试 | 在每个后端上分别跑同一批断言 | 只回答「是否通过」，不回答「四个后端是否算出同一个值」 |
| wasm 运行时 / 组件模型绑定 | 让 MoonBit 能跑在 wasm 上 | 不涉及语义一致性验证 |
| Csmith / C-Reduce（其他语言生态） | 面向 C 编译器的差分测试与反例最小化 | 目标不是 MoonBit，程序模型与收缩算法也不同 |

## 规范裁定层的原创性

工具从「报告差异」升级到「判定谁违反规范」，这一层是本项目自行设计的，
在可检索范围内未发现同类实现：

- **三级判定模型**：`SPEC-VIOLATION` / `IMPLEMENTATION-FREEDOM` / `UNDETERMINED`。
  常见差分工具只有「一致/不一致」两态，把实现自由度与真缺陷混在一起；
  本项目把二者分开，并强制在缺依据时输出 `UNDETERMINED` 而不是猜测。
- **规范侧期望值表**：把语言文档里可引用的条款（`Int` 的二补数回绕语义、
  IEEE 754-2019 §6.2.3 的 NaN 符号位条款）编码成可执行的判定依据，
  报告中直接引用出处。
- **终止性差异的静态定位**：后端 trap 时转录被整体丢弃、步号归零，
  常规「按步号取值」的做法会把无辜后端判成违规方。
  本项目改用 `find_static_violation` 按程序结构定位真正的溢出点，
  再回到目标步取值——这个坑是实测踩到并修掉的，不是设计时的假设。

以上三点均为本仓库原创，方法论文参考见 `README.md` 的「关于参考项目的说明」。

## 代码来源声明

- 本仓库代码全部新写，未复制、未改写任何第三方源代码；
- 未引入任何第三方 MoonBit 包，仅依赖 `moonbitlang/core`；
- 文中提到的外部项目仅作为方法论参考，未使用其代码或测试语料。

如后续引入外部语料，将在对应文件的头部标注来源与许可证。
