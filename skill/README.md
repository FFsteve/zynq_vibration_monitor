# 可复用的FIR验证技能

入口为[fir-validation/SKILL.md](fir-validation/SKILL.md)，包含适用范围、定点合同、实际验证入口、失败条件和资源取证。它基于本项目已执行的Python、ModelSim/XSim和Vivado流程，不是通用占位说明；未安装或修改全局技能目录。

适合调整FIR/去直流参数、检查舍入和溢出、运行受影响自检及收集竞赛资源时序证据。用于其他项目时须重建数值与时序合同，不能直接套用本项目哈希和历史结论。

结构验证只检查格式和元数据。实际流程的依据是[第四阶段](../report/stage4_validation.md)、[第六阶段](../report/stage6_validation.md)及[第七阶段](../report/stage7_validation.md)的真实工具证据；不声称已进行独立代理行为评测。
