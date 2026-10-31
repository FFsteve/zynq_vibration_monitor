# 本文件仅用于实现阶段，在综合后读取；依赖当前 top 的实际层次。
# 精确切断异步串口输入到第一级采样 D 的路径，禁止豁免整条同步链。
# 对象数量检查放在 Tcl 验证脚本中，XDC 只保留受支持的约束命令。
set_false_path -from [get_ports pl_rx] -to [get_pins u_core/u_rx/rx_meta_reg/D]
