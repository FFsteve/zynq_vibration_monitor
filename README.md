# Zynq-7010 vibration monitor — Codex handoff

This repository is an initial **context handoff**, not an implemented or validated FPGA project. All RTL, simulation and board test results are pending. Read `AGENTS.md`, `docs/project_context.md`, and `docs/hardware_pinmap.md` before changing anything.

Goal: MPU6050 -> STM32F103C8T6 I2C -> Zynq-7010 PL UART RX -> packet parser -> (future FIR/feature extraction) -> UART TX -> PC. PS is out of scope for the first iteration.

Start with `docs/next_task.md`. Check physical board revision and UART voltage, and confirm constraints before wiring or programming.

The four original vendor PDFs are included for *local Codex reference* in `docs/hardware/` and excluded from Git by default. Check the authors' redistribution terms before publishing any PDFs to the mandatory public GitHub/Gitee repository; publish source links and derived pinmap documentation when redistribution is not permitted.
