create_debug_core u_ila_0 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT 2 [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_0]
set_property C_DATA_DEPTH 1024 [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL true [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
set_property port_width 1 [get_debug_ports u_ila_0/clk]
connect_debug_port u_ila_0/clk [get_nets [list clk_IBUF_BUFG]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
set_property port_width 32 [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets [list {debug_aborted_windows_o[0]} {debug_aborted_windows_o[1]} {debug_aborted_windows_o[2]} {debug_aborted_windows_o[3]} {debug_aborted_windows_o[4]} {debug_aborted_windows_o[5]} {debug_aborted_windows_o[6]} {debug_aborted_windows_o[7]} {debug_aborted_windows_o[8]} {debug_aborted_windows_o[9]} {debug_aborted_windows_o[10]} {debug_aborted_windows_o[11]} {debug_aborted_windows_o[12]} {debug_aborted_windows_o[13]} {debug_aborted_windows_o[14]} {debug_aborted_windows_o[15]} {debug_aborted_windows_o[16]} {debug_aborted_windows_o[17]} {debug_aborted_windows_o[18]} {debug_aborted_windows_o[19]} {debug_aborted_windows_o[20]} {debug_aborted_windows_o[21]} {debug_aborted_windows_o[22]} {debug_aborted_windows_o[23]} {debug_aborted_windows_o[24]} {debug_aborted_windows_o[25]} {debug_aborted_windows_o[26]} {debug_aborted_windows_o[27]} {debug_aborted_windows_o[28]} {debug_aborted_windows_o[29]} {debug_aborted_windows_o[30]} {debug_aborted_windows_o[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
set_property port_width 3 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list {debug_alarm_axes_o[0]} {debug_alarm_axes_o[1]} {debug_alarm_axes_o[2]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
set_property port_width 32 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets [list {debug_completed_count_o[0]} {debug_completed_count_o[1]} {debug_completed_count_o[2]} {debug_completed_count_o[3]} {debug_completed_count_o[4]} {debug_completed_count_o[5]} {debug_completed_count_o[6]} {debug_completed_count_o[7]} {debug_completed_count_o[8]} {debug_completed_count_o[9]} {debug_completed_count_o[10]} {debug_completed_count_o[11]} {debug_completed_count_o[12]} {debug_completed_count_o[13]} {debug_completed_count_o[14]} {debug_completed_count_o[15]} {debug_completed_count_o[16]} {debug_completed_count_o[17]} {debug_completed_count_o[18]} {debug_completed_count_o[19]} {debug_completed_count_o[20]} {debug_completed_count_o[21]} {debug_completed_count_o[22]} {debug_completed_count_o[23]} {debug_completed_count_o[24]} {debug_completed_count_o[25]} {debug_completed_count_o[26]} {debug_completed_count_o[27]} {debug_completed_count_o[28]} {debug_completed_count_o[29]} {debug_completed_count_o[30]} {debug_completed_count_o[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe3]
set_property port_width 35 [get_debug_ports u_ila_0/probe3]
connect_debug_port u_ila_0/probe3 [get_nets [list {debug_ms_y_o[0]} {debug_ms_y_o[1]} {debug_ms_y_o[2]} {debug_ms_y_o[3]} {debug_ms_y_o[4]} {debug_ms_y_o[5]} {debug_ms_y_o[6]} {debug_ms_y_o[7]} {debug_ms_y_o[8]} {debug_ms_y_o[9]} {debug_ms_y_o[10]} {debug_ms_y_o[11]} {debug_ms_y_o[12]} {debug_ms_y_o[13]} {debug_ms_y_o[14]} {debug_ms_y_o[15]} {debug_ms_y_o[16]} {debug_ms_y_o[17]} {debug_ms_y_o[18]} {debug_ms_y_o[19]} {debug_ms_y_o[20]} {debug_ms_y_o[21]} {debug_ms_y_o[22]} {debug_ms_y_o[23]} {debug_ms_y_o[24]} {debug_ms_y_o[25]} {debug_ms_y_o[26]} {debug_ms_y_o[27]} {debug_ms_y_o[28]} {debug_ms_y_o[29]} {debug_ms_y_o[30]} {debug_ms_y_o[31]} {debug_ms_y_o[32]} {debug_ms_y_o[33]} {debug_ms_y_o[34]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe4]
set_property port_width 18 [get_debug_ports u_ila_0/probe4]
connect_debug_port u_ila_0/probe4 [get_nets [list {debug_peak_x_o[0]} {debug_peak_x_o[1]} {debug_peak_x_o[2]} {debug_peak_x_o[3]} {debug_peak_x_o[4]} {debug_peak_x_o[5]} {debug_peak_x_o[6]} {debug_peak_x_o[7]} {debug_peak_x_o[8]} {debug_peak_x_o[9]} {debug_peak_x_o[10]} {debug_peak_x_o[11]} {debug_peak_x_o[12]} {debug_peak_x_o[13]} {debug_peak_x_o[14]} {debug_peak_x_o[15]} {debug_peak_x_o[16]} {debug_peak_x_o[17]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe5]
set_property port_width 18 [get_debug_ports u_ila_0/probe5]
connect_debug_port u_ila_0/probe5 [get_nets [list {debug_peak_z_o[0]} {debug_peak_z_o[1]} {debug_peak_z_o[2]} {debug_peak_z_o[3]} {debug_peak_z_o[4]} {debug_peak_z_o[5]} {debug_peak_z_o[6]} {debug_peak_z_o[7]} {debug_peak_z_o[8]} {debug_peak_z_o[9]} {debug_peak_z_o[10]} {debug_peak_z_o[11]} {debug_peak_z_o[12]} {debug_peak_z_o[13]} {debug_peak_z_o[14]} {debug_peak_z_o[15]} {debug_peak_z_o[16]} {debug_peak_z_o[17]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe6]
set_property port_width 8 [get_debug_ports u_ila_0/probe6]
connect_debug_port u_ila_0/probe6 [get_nets [list {debug_seq_start_o[0]} {debug_seq_start_o[1]} {debug_seq_start_o[2]} {debug_seq_start_o[3]} {debug_seq_start_o[4]} {debug_seq_start_o[5]} {debug_seq_start_o[6]} {debug_seq_start_o[7]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe7]
set_property port_width 18 [get_debug_ports u_ila_0/probe7]
connect_debug_port u_ila_0/probe7 [get_nets [list {debug_rms_z_o[0]} {debug_rms_z_o[1]} {debug_rms_z_o[2]} {debug_rms_z_o[3]} {debug_rms_z_o[4]} {debug_rms_z_o[5]} {debug_rms_z_o[6]} {debug_rms_z_o[7]} {debug_rms_z_o[8]} {debug_rms_z_o[9]} {debug_rms_z_o[10]} {debug_rms_z_o[11]} {debug_rms_z_o[12]} {debug_rms_z_o[13]} {debug_rms_z_o[14]} {debug_rms_z_o[15]} {debug_rms_z_o[16]} {debug_rms_z_o[17]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe8]
set_property port_width 32 [get_debug_ports u_ila_0/probe8]
connect_debug_port u_ila_0/probe8 [get_nets [list {debug_rx_frame_count_o[0]} {debug_rx_frame_count_o[1]} {debug_rx_frame_count_o[2]} {debug_rx_frame_count_o[3]} {debug_rx_frame_count_o[4]} {debug_rx_frame_count_o[5]} {debug_rx_frame_count_o[6]} {debug_rx_frame_count_o[7]} {debug_rx_frame_count_o[8]} {debug_rx_frame_count_o[9]} {debug_rx_frame_count_o[10]} {debug_rx_frame_count_o[11]} {debug_rx_frame_count_o[12]} {debug_rx_frame_count_o[13]} {debug_rx_frame_count_o[14]} {debug_rx_frame_count_o[15]} {debug_rx_frame_count_o[16]} {debug_rx_frame_count_o[17]} {debug_rx_frame_count_o[18]} {debug_rx_frame_count_o[19]} {debug_rx_frame_count_o[20]} {debug_rx_frame_count_o[21]} {debug_rx_frame_count_o[22]} {debug_rx_frame_count_o[23]} {debug_rx_frame_count_o[24]} {debug_rx_frame_count_o[25]} {debug_rx_frame_count_o[26]} {debug_rx_frame_count_o[27]} {debug_rx_frame_count_o[28]} {debug_rx_frame_count_o[29]} {debug_rx_frame_count_o[30]} {debug_rx_frame_count_o[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe9]
set_property port_width 18 [get_debug_ports u_ila_0/probe9]
connect_debug_port u_ila_0/probe9 [get_nets [list {debug_rms_y_o[0]} {debug_rms_y_o[1]} {debug_rms_y_o[2]} {debug_rms_y_o[3]} {debug_rms_y_o[4]} {debug_rms_y_o[5]} {debug_rms_y_o[6]} {debug_rms_y_o[7]} {debug_rms_y_o[8]} {debug_rms_y_o[9]} {debug_rms_y_o[10]} {debug_rms_y_o[11]} {debug_rms_y_o[12]} {debug_rms_y_o[13]} {debug_rms_y_o[14]} {debug_rms_y_o[15]} {debug_rms_y_o[16]} {debug_rms_y_o[17]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe10]
set_property port_width 35 [get_debug_ports u_ila_0/probe10]
connect_debug_port u_ila_0/probe10 [get_nets [list {debug_ms_x_o[0]} {debug_ms_x_o[1]} {debug_ms_x_o[2]} {debug_ms_x_o[3]} {debug_ms_x_o[4]} {debug_ms_x_o[5]} {debug_ms_x_o[6]} {debug_ms_x_o[7]} {debug_ms_x_o[8]} {debug_ms_x_o[9]} {debug_ms_x_o[10]} {debug_ms_x_o[11]} {debug_ms_x_o[12]} {debug_ms_x_o[13]} {debug_ms_x_o[14]} {debug_ms_x_o[15]} {debug_ms_x_o[16]} {debug_ms_x_o[17]} {debug_ms_x_o[18]} {debug_ms_x_o[19]} {debug_ms_x_o[20]} {debug_ms_x_o[21]} {debug_ms_x_o[22]} {debug_ms_x_o[23]} {debug_ms_x_o[24]} {debug_ms_x_o[25]} {debug_ms_x_o[26]} {debug_ms_x_o[27]} {debug_ms_x_o[28]} {debug_ms_x_o[29]} {debug_ms_x_o[30]} {debug_ms_x_o[31]} {debug_ms_x_o[32]} {debug_ms_x_o[33]} {debug_ms_x_o[34]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe11]
set_property port_width 18 [get_debug_ports u_ila_0/probe11]
connect_debug_port u_ila_0/probe11 [get_nets [list {debug_rms_x_o[0]} {debug_rms_x_o[1]} {debug_rms_x_o[2]} {debug_rms_x_o[3]} {debug_rms_x_o[4]} {debug_rms_x_o[5]} {debug_rms_x_o[6]} {debug_rms_x_o[7]} {debug_rms_x_o[8]} {debug_rms_x_o[9]} {debug_rms_x_o[10]} {debug_rms_x_o[11]} {debug_rms_x_o[12]} {debug_rms_x_o[13]} {debug_rms_x_o[14]} {debug_rms_x_o[15]} {debug_rms_x_o[16]} {debug_rms_x_o[17]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe12]
set_property port_width 32 [get_debug_ports u_ila_0/probe12]
connect_debug_port u_ila_0/probe12 [get_nets [list {debug_filter_restart_count_o[0]} {debug_filter_restart_count_o[1]} {debug_filter_restart_count_o[2]} {debug_filter_restart_count_o[3]} {debug_filter_restart_count_o[4]} {debug_filter_restart_count_o[5]} {debug_filter_restart_count_o[6]} {debug_filter_restart_count_o[7]} {debug_filter_restart_count_o[8]} {debug_filter_restart_count_o[9]} {debug_filter_restart_count_o[10]} {debug_filter_restart_count_o[11]} {debug_filter_restart_count_o[12]} {debug_filter_restart_count_o[13]} {debug_filter_restart_count_o[14]} {debug_filter_restart_count_o[15]} {debug_filter_restart_count_o[16]} {debug_filter_restart_count_o[17]} {debug_filter_restart_count_o[18]} {debug_filter_restart_count_o[19]} {debug_filter_restart_count_o[20]} {debug_filter_restart_count_o[21]} {debug_filter_restart_count_o[22]} {debug_filter_restart_count_o[23]} {debug_filter_restart_count_o[24]} {debug_filter_restart_count_o[25]} {debug_filter_restart_count_o[26]} {debug_filter_restart_count_o[27]} {debug_filter_restart_count_o[28]} {debug_filter_restart_count_o[29]} {debug_filter_restart_count_o[30]} {debug_filter_restart_count_o[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe13]
set_property port_width 8 [get_debug_ports u_ila_0/probe13]
connect_debug_port u_ila_0/probe13 [get_nets [list {debug_seq_end_o[0]} {debug_seq_end_o[1]} {debug_seq_end_o[2]} {debug_seq_end_o[3]} {debug_seq_end_o[4]} {debug_seq_end_o[5]} {debug_seq_end_o[6]} {debug_seq_end_o[7]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe14]
set_property port_width 32 [get_debug_ports u_ila_0/probe14]
connect_debug_port u_ila_0/probe14 [get_nets [list {debug_dropped_count_o[0]} {debug_dropped_count_o[1]} {debug_dropped_count_o[2]} {debug_dropped_count_o[3]} {debug_dropped_count_o[4]} {debug_dropped_count_o[5]} {debug_dropped_count_o[6]} {debug_dropped_count_o[7]} {debug_dropped_count_o[8]} {debug_dropped_count_o[9]} {debug_dropped_count_o[10]} {debug_dropped_count_o[11]} {debug_dropped_count_o[12]} {debug_dropped_count_o[13]} {debug_dropped_count_o[14]} {debug_dropped_count_o[15]} {debug_dropped_count_o[16]} {debug_dropped_count_o[17]} {debug_dropped_count_o[18]} {debug_dropped_count_o[19]} {debug_dropped_count_o[20]} {debug_dropped_count_o[21]} {debug_dropped_count_o[22]} {debug_dropped_count_o[23]} {debug_dropped_count_o[24]} {debug_dropped_count_o[25]} {debug_dropped_count_o[26]} {debug_dropped_count_o[27]} {debug_dropped_count_o[28]} {debug_dropped_count_o[29]} {debug_dropped_count_o[30]} {debug_dropped_count_o[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe15]
set_property port_width 35 [get_debug_ports u_ila_0/probe15]
connect_debug_port u_ila_0/probe15 [get_nets [list {debug_ms_z_o[0]} {debug_ms_z_o[1]} {debug_ms_z_o[2]} {debug_ms_z_o[3]} {debug_ms_z_o[4]} {debug_ms_z_o[5]} {debug_ms_z_o[6]} {debug_ms_z_o[7]} {debug_ms_z_o[8]} {debug_ms_z_o[9]} {debug_ms_z_o[10]} {debug_ms_z_o[11]} {debug_ms_z_o[12]} {debug_ms_z_o[13]} {debug_ms_z_o[14]} {debug_ms_z_o[15]} {debug_ms_z_o[16]} {debug_ms_z_o[17]} {debug_ms_z_o[18]} {debug_ms_z_o[19]} {debug_ms_z_o[20]} {debug_ms_z_o[21]} {debug_ms_z_o[22]} {debug_ms_z_o[23]} {debug_ms_z_o[24]} {debug_ms_z_o[25]} {debug_ms_z_o[26]} {debug_ms_z_o[27]} {debug_ms_z_o[28]} {debug_ms_z_o[29]} {debug_ms_z_o[30]} {debug_ms_z_o[31]} {debug_ms_z_o[32]} {debug_ms_z_o[33]} {debug_ms_z_o[34]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe16]
set_property port_width 18 [get_debug_ports u_ila_0/probe16]
connect_debug_port u_ila_0/probe16 [get_nets [list {debug_peak_y_o[0]} {debug_peak_y_o[1]} {debug_peak_y_o[2]} {debug_peak_y_o[3]} {debug_peak_y_o[4]} {debug_peak_y_o[5]} {debug_peak_y_o[6]} {debug_peak_y_o[7]} {debug_peak_y_o[8]} {debug_peak_y_o[9]} {debug_peak_y_o[10]} {debug_peak_y_o[11]} {debug_peak_y_o[12]} {debug_peak_y_o[13]} {debug_peak_y_o[14]} {debug_peak_y_o[15]} {debug_peak_y_o[16]} {debug_peak_y_o[17]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe17]
set_property port_width 32 [get_debug_ports u_ila_0/probe17]
connect_debug_port u_ila_0/probe17 [get_nets [list {debug_window_id_o[0]} {debug_window_id_o[1]} {debug_window_id_o[2]} {debug_window_id_o[3]} {debug_window_id_o[4]} {debug_window_id_o[5]} {debug_window_id_o[6]} {debug_window_id_o[7]} {debug_window_id_o[8]} {debug_window_id_o[9]} {debug_window_id_o[10]} {debug_window_id_o[11]} {debug_window_id_o[12]} {debug_window_id_o[13]} {debug_window_id_o[14]} {debug_window_id_o[15]} {debug_window_id_o[16]} {debug_window_id_o[17]} {debug_window_id_o[18]} {debug_window_id_o[19]} {debug_window_id_o[20]} {debug_window_id_o[21]} {debug_window_id_o[22]} {debug_window_id_o[23]} {debug_window_id_o[24]} {debug_window_id_o[25]} {debug_window_id_o[26]} {debug_window_id_o[27]} {debug_window_id_o[28]} {debug_window_id_o[29]} {debug_window_id_o[30]} {debug_window_id_o[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe18]
set_property port_width 1 [get_debug_ports u_ila_0/probe18]
connect_debug_port u_ila_0/probe18 [get_nets [list debug_alarm_valid_o]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe19]
set_property port_width 1 [get_debug_ports u_ila_0/probe19]
connect_debug_port u_ila_0/probe19 [get_nets [list debug_feature_valid_o]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe20]
set_property port_width 1 [get_debug_ports u_ila_0/probe20]
connect_debug_port u_ila_0/probe20 [get_nets [list debug_quality_valid_o]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk_IBUF_BUFG]
