# 验收对照

九条验收要求逐条对应到仓库里的文件或一条可执行的命令。每条都能当场复核，
不需要相信任何文档里的说法。

版本：`wuhaiting321/moondiff` 0.1.0 ｜ 核验日期 2026-11-23

| # | 验收要求 | 证据 | 复核方式 |
| --- | --- | --- | --- |
| 1 | 主要实现语言为 MoonBit，`moonc` ≥ 0.10.16 | 源码 4820 行 `.mbt`（`src/` 8 个包 + `cmd/` 2 个可执行 + `probes/`），`scripts/` 只做编排；实测 `moonc v0.10.16+b1a0e846e`，CI 装最新版（0.10.21）并打印版本 | `moon version --all`；`find src cmd probes -name '*.mbt' \| xargs wc -l \| tail -1` |
| 2 | GitHub 仓库公开、提交记录清晰 | https://github.com/wuhaiting321/MoonDiff ，提交按「一个动作一个提交」拆分，正文写明改了什么、为什么 | `git log --oneline` |
| 3 | 结构清晰、能完成声明的核心功能 | `src/` 按职责分包：`core`（值模型与差异）/ `spec`（程序表示与编解码）/ `exec`（参照解释器）/ `gen`（生成器）/ `shrink`（收缩与复跑）/ `oracle`（四档裁定）/ `report`（渲染）；数据流见 `docs/ARCHITECTURE.md` | `moon check`；`docs/ARCHITECTURE.md`「包职责」 |
| 4 | README 说明目标、安装、用法、示例且可复现 | `README.md`：项目简介（目标）、安装与运行（两条安装路径 + 环境要求）、最小示例（一条命令 + 实跑输出）、完整验证（四条命令） | 按 `README.md`「安装与运行」原样执行 |
| 5 | 持续集成覆盖检查、构建、测试 | `.github/workflows/ci.yml`：`unit` 作业在 wasm / wasm-gc / js / native 四个目标上各跑 `moon check` → `moon build` → `moon test`；`differential` 作业跑自举、回归、四后端普查、源码探针、覆盖核对、收缩复跑 | GitHub Actions 页面最近一次 `MoonDiff CI` |
| 6 | 至少一个可运行示例 | `examples/min-div-overflow.json`（3 条指令）+ `examples/` 下另 9 个用例；`bash scripts/matrix.sh examples/min-div-overflow.json` 一条命令产出矩阵、归因、裁定三段 | `bash scripts/matrix.sh examples/min-div-overflow.json` |
| 7 | 完整测试覆盖核心功能路径 | 62 个单元测试，分布在 `src/{core,spec,exec,gen,shrink,oracle,report}/*_wbtest.mbt`；另有 `scripts/selfcheck.sh`（工具自举）、`scripts/regress.sh`（11 项基线）、`scripts/source-probe.sh`（30 个真实库探针） | `moon test` |
| 8 | 发布到 mooncakes.io | `wuhaiting321/moondiff` 0.1.0 | `moon add wuhaiting321/moondiff` |
| 9 | OSI 认可的开源许可证，无侵权移植 | `LICENSE` = Apache-2.0；`moon.mod` 中 `license = "Apache-2.0"`；无第三方依赖、未移植任何项目（`README.md`「是否为原创项目」） | `head -3 LICENSE`；`grep license moon.mod` |

## 两处口径说明

**第 5 条的「构建」与「测试」分开**：`moon check` 只做类型检查，链接失败（缺符号、
目标不支持的调用）只有 `moon build` 会暴露；`moon test` 会顺带构建，但它的失败信息
混在测试报告里。三条各自独立，失败点才定位得清。

**第 7 条不按行覆盖率算**：本项目要证明的是「同一份程序在四个后端上算得一样」，
行覆盖率对这个命题没有意义（一个函数被调用到、但只在 wasm 上被调用到，覆盖率照样 100%）。
所以这里用三类证据：单元测试（本包逻辑）、自举（工具自身在四后端输出逐字节一致）、
真实库探针（30 个用例逐字节比对）。探针覆盖的接口比例与不覆盖的边界写在
`README.md`「结论边界」与 `docs/SCOPE.md`，那个数字不含任何「保证」的意思。
