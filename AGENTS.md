# Codex project instructions

- This is a one-person student FPGA contest project. Prefer a **small, independently testable change** to a full system rewrite.
- Explain the design first: inputs/outputs, registers, FSM states, cycle timing and verification criteria. Wait for approval before writing major new RTL.
- RTL: Verilog; STM32: Keil MDK + STM32F10x Standard Peripheral Library, **not HAL/CubeMX**. First revision is PL-only; do not introduce PS/AXI/Linux/PYNQ without permission.
- Read `docs/project_context.md`, `docs/hardware_pinmap.md` and the actual schematic PDFs for any pinout/power assertion. If not confirmed, mark as unverified; do not guess physical connections.
- For each RTL module, provide a matching self-checking testbench with normal, error and recovery cases. Never claim a simulation, Vivado build or board test passed unless actually run; report unavailable tools.
- UART packet format is a **draft**; see `docs/project_context.md`. Get approval before changing it. Every packet parser must recover after corrupted/truncated frames.
- Run available checks when possible; report exact commands, results, modified files, remaining risks and next steps.
- Never modify generated Vivado caches or board flashing settings unless requested. Do not use destructive shell commands or push to GitHub without approval.
- Record important AI suggestions, corrections and test evidence in `report/ai_devlog.md`. Distinguish hypotheses from verified results.
- Keep project paths and filenames ASCII. Leave proprietary or unlicensed third-party examples outside the public repo unless redistribution is permitted; check PDFs' license before public release.
