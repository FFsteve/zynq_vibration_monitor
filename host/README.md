# PC 原始数据记录工具

`protocol.py` 独立实现当前十字节协议；`capture.py` 将原始二进制、三轴 CSV 和诊断 JSON 保存到新目录。`test_protocol.py` 为自检，`check_stage3_captures.py` 将两种 FPGA 仿真器的捕获送入实际工具，并比对独立期望。

## 离线验证

在仓库根目录运行，Python 3.10 或以上，无需第三方依赖：

```powershell
python -X utf8 -m unittest discover -s host -p test_protocol.py -v
python -X utf8 host/check_stage3_captures.py
```

第二条需要先完成两种仿真器的 top 自检。单独重放可执行：

```powershell
python -X utf8 host/capture.py --input-bin build/modelsim_stage3/top/top_frame_capture.bin --mode frame --expected-csv build/modelsim_stage3/top/top_frame_expected.csv --expect-count 24 --output build/pc_manual_frame_01
```

输出目录已有 capture.bin、samples.csv 或 stats.json 时拒绝覆盖，请换新目录。离线 CSV 的 host_time_ns 固定为 0，避免伪造板卡采样时间。

## 未来在线记录

当前暂缓上板，以下命令仅作为以后操作说明，本轮未执行。确认实际 COM 口和输出模式后：

```powershell
python -m pip install -r host/requirements.txt
python -X utf8 host/capture.py --port COM5 --mode frame --baud 115200 --seconds 10 --output build/pc_live_frame_01
```

COM5 仅为示例。ACK 模式改为 `--mode ack`；工具只接收，不向 STM32 或 FPGA 发命令。Ctrl+C 会关闭记录并保存统计。ACK 每次只有 06，不能检查序号或三轴；完整内容必须使用整包模式。当前执行环境未安装 pyserial，未测试真实串口分支。

在线时间戳是 PC 收到分块的时间，同一分块的多组样本时间戳可能相同，不能据此精确测传感器采样周期。默认记录不会在内存累计全部样本；仅指定 expected-csv 时保留样本用于比对。

SEQ 按模 256 统计跳号和重复，不可把 gap_mod256_total 当作跨任意时间的真实丢包数。PC 滑动解析器不以操作系统分块间隔模拟 PL 的 2 ms 超时。坏包后继续搜索；XOR 无法检测所有损坏。原始加速度仍含偏置和重力贡献，本工具不做 FIR、单位换算或故障分类。
