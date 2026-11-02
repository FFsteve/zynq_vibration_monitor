# 可复用技能包

本文件是竞赛技能包入口；工程根目录的 README.md 是项目简介与复现入口，两者用途不同。技能来自“分析 UART RX 设计与硬件约束”开始，到本次聊天中校准、ILA 实测、蜂鸣器上板与交付的完整流程，不限于 FIR 编码。

## 选择技能与使用方法

| 技能/资源 | 适用场景 | 使用方法 | 失效条件/边界 | 已验证效果与来源 |
|---|---|---|---|---|
| [pl-sensor-workflow](pl-sensor-workflow/SKILL.md) | 学生 FPGA 传感器项目，从图纸、协议、分期到板测和交付 | 把该文件夹复制到新项目的技能目录；给 AI 本项目合同或填写 references/project_profile.json，并说明当前处于哪阶段 | 不能照搬其他板的引脚、时钟、电压、模块校准和阈值；不自动授权烧录/推送 | 本案例分七阶段完成数字链路并由实物多源交叉验证，另完成校准与蜂鸣器；原始协作正文在 report/ai_records/ |
| [fir-validation](fir-validation/SKILL.md) | 已有 FIR 的数值、RTL 与综合证据核对 | 在本项目按技能链接运行阶段入口；异项目重新定义数值/周期合同 | 不是通用系数或波形通过证明；更改格式必须重建参考 | 阶段4/5/6/7 的真实 ModelSim、XSim、Vivado 结果 |
| [流程清单](pl-sensor-workflow/references/workflow.md) | 新题目的开发与验收切分 | 按当前阶段使用输入、产物与停止条件，先固定合同再实现小模块 | 竞赛时间不足时不能把扩展工程测试变成全部必做 | 从基础通信到独立蜂鸣器扩展的增量开发经验 |
| [排错清单](pl-sensor-workflow/references/pitfalls.md) | 接线、采样、ILA、工具与版本不一致 | 按触发条件选择条目，执行定位并保留反例 | 只凭截图、不同时间数据或未知初态时需降低结论范围 | U13→U18、CDC 载入阶段、bit/ltx 混配、窗口匹配、短记录校准、测试范围过度等实际问题 |
| [提示词模板](pl-sensor-workflow/references/prompts.md) | 换题目后与 AI 分阶段协作 | 替换方括号输入，提供已有证据，使用可核验完成条件 | 未提供资料时 AI 必须列出未知，不能补造引脚或实测 | 对照两份实际聊天正文及 ai_devlog 中的纠错 |
| scripts/check_csv.py | 已有独立参考与实测列的整数精确对照 | 提供 CSV 和 JSON 列映射，可用于不同轴数/不同列名；见下方 | 不生成黄金参考，不能证明产生 expected 的算法正确；不能把采样缺失当零 | 本次实际重放 4914 个完整回包；另用两列异题样例及错误/空记录反例测试 |

```powershell
python -X utf8 skill/pl-sensor-workflow/scripts/check_csv.py --csv report/evidence/filter_test_3_20261101_analysis/comparison.csv --profile skill/pl-sensor-workflow/references/project_profile.json
python -X utf8 skill/pl-sensor-workflow/scripts/check_csv.py --self-test
```

自检覆盖正确、错误、空文件、列缺失与恢复重新检查；真实对照和自检结果见 report/delivery_validation_20261102.json。技能结构校验只证明格式，不等于独立行为评测。没有声称在另一块实板或独立 AI 代理上验证过全部流程。

## 迁移到陌生题目

复制 pl-sensor-workflow/ 即可获得独立的 SKILL.md、参考清单、提示词、列映射示例和仅依赖 Python 标准库的校验脚本。references/workflow.md 不要求本项目目录或 Zynq；将板卡、帧格式、处理合同、复现工具和验收证据替换为新项目内容。references/case_study.md 单独保留本项目经验来源；跨项目时无需照抄其常数。

这不是 PYNQ Skill，未申报通用 PYNQ 加分；本题纯 PL 方案没有因此增加 PS 或 DMA。真实效果以现有工程证据和实际脚本运行结果为限。
