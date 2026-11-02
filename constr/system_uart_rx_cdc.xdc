# 仅用于新增system_top的实现阶段；保留第二级同步路径的严格计时。
set_false_path -from [get_ports pl_rx] -to [get_pins u_core/u_processing/filtering/communication/u_rx/rx_meta_reg/D]

