# 精选真实测量与重放

filter_test_3/ 中的 uart_d0.csv.gz、uart_d1.csv.gz 是原 ATK 导出 CSV 的无损 gzip 压缩，解压字节未作修改；原始 SHA256 与压缩文件身份见 source_identity.json。D0 是已校准传感器输入，D1 是滤波回传，4915 输入/4914 完整输出；末尾6个字节属于采集右边界，不计入中途丢包。

从工程根目录执行 `python -X utf8 scripts/replay_delivery.py`，会临时解压、逐位/逐字节检查、独立协议解码，再以真实输入重算去直流/FIR并对照完整输出。需要NumPy；若本机系统临时目录不可写，可给当前进程的 TEMP/TMP 指定一个可写临时目录，不改变数据或期望。

ila/static.csv、motion.csv 保留 filter_test_4 的原始 ILA CSV。它们与该次参考的对应和恢复边界见 report/filter_test_4_validation_20261101.md 及 report/evidence/filter_test_4_20261101_analysis/；并非本次重新采集。

完整六面、长采样、I2C与ATK工程原件继续留在原工作区；本包收录汇总和选定复现证据，没有声称在缺少原件时可以重跑全部历史分析。模拟与实测、原测与重建不能混为一类。
