# Codex 项目指令

- 这是由一名学生独立完成的 FPGA 竞赛项目。优先进行**规模小、可独立测试的修改**，避免整体重写系统。
- 先解释设计，包括输入输出、寄存器、状态机、周期时序和验收标准；编写较大规模的新 RTL 前，等待用户批准。
- RTL 使用 Verilog；STM32 使用 Keil MDK 和 STM32F10x 标准外设库，**不使用 HAL/CubeMX**。第一版仅使用 PL；未经批准，不引入 PS、AXI、Linux 或 PYNQ。
- 涉及引脚或供电结论时，必须阅读 `docs/project_context.md`、`docs/hardware_pinmap.md` 和实际原理图 PDF。不能确认的内容应标注“未验证”，不得猜测物理连接。
- 每个 RTL 模块必须配套自检 Testbench，包含正常、错误和恢复用例。只有实际执行后才能声称仿真、Vivado 构建或板测通过；工具不可用时应如实说明。
- UART 数据包当前按第二阶段约定实现，详见 `docs/project_context.md` 和 `docs/stage2_design.md`。既有十字节布局保持不变；后续修改协议前需获批准。每个包解析器都必须支持损坏帧和截断帧后的恢复。
- 尽可能运行现有检查，并报告准确命令、结果、修改文件、剩余风险和下一步。
- 未经要求，不修改 Vivado 自动生成的缓存或板卡烧录设置。未经批准，不执行破坏性命令或推送到 GitHub。
- 在 `report/ai_devlog.md` 中记录重要 AI 建议、纠错和测试证据，区分假设与已验证结果。
- 项目路径和文件名保持 ASCII。专有或无再分发许可的第三方示例不得纳入公开仓库；公开 PDF 前先核实授权。
- **后续编写或修改的 Markdown 文档正文、标题、表格说明，以及 RTL、Testbench 和脚本中的说明性注释，统一使用中文。** 文件名、代码标识符、命令、工具名称和自动解析所需的日志标记保留原样；`synthesis translate_off/on` 等工具指令不得翻译。文件使用 UTF-8；带中文注释且需兼容 Windows PowerShell 5.1 的 `.ps1` 使用带 BOM 的 UTF-8。
