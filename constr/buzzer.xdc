# 底板V3.9第1/5页及核心板2v5第3/7/12页：BEEP经X3.60接M14/Bank35。
# 图纸及厂家资料确认有源蜂鸣器由S8050高电平驱动，默认低电平静音。
set_property -dict {PACKAGE_PIN M14 IOSTANDARD LVCMOS33 DRIVE 8 SLEW SLOW} [get_ports beep]
# 蜂鸣器不是由PL时钟采样的外部同步接收端；内部输出寄存器路径仍正常计时。
set_false_path -to [get_ports beep]
