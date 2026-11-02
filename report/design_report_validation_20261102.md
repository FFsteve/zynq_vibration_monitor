# 设计报告当前归档与核查记录

日期：2026-11-02。当前报告正文及实物照片已补齐，用户明确指定保留中文文件名：

- Word：report/技术文档word版.docx。
- PDF：report/技术文档pdf版.pdf，共23页。

两份文件已同步到原工作区和zynq_vibration_monitor_final/report/。README、当前交付说明及package_manifest.json均以这两份文件为入口；清单中设计报告完成状态为true，已移除照片待补计数和当前待办说明。仅这两份报告按用户要求保留中文名称，不将其误报为满足原先纯英文命名约定。

## 本次实际检查与边界

读取当前DOCX压缩结构及正文，压缩成员完整、未发现原照片占位文字；读取当前PDF确认23页。两份文件的内容和图片未被本次更新修改，原工作区副本与用户最终包中的文件SHA256一致。核对README本地报告链接和包清单中的路径、后缀及指纹。

本次只更新引用、状态及核验/组包脚本，不修改RTL、STM32、bit、ltx、hex，不重新进行仿真、综合实现或板测，不执行Git提交或推送。PDF页数检查不等于本轮对照片版23页重新做完整视觉审核。

## 初稿排版检查的历史范围

原始模板F:/嵌赛/技术文档模板.docx的SHA256为d15a2aa186f600cb9c234bffd9deff0c4e9b05c569643d8a81d536f66f424f0c。初稿按模板保留A4、单节、页边距、字体体系、官方页眉与页脚PAGE字段、五部分及小节顺序；20个未编辑部件逐字节一致。

初稿为22页，在补图前实际通过Word原生只读PDF导出，经render_docx.py与render_and_diff.py适配、PDFium栅格化后逐页检查；section_audit.py、style_lint.py、fields_report.py、images_audit.py、heading_audit.py、footnotes_report.py均退出0。该历史逐页结论对应初稿指纹6a0ca3cec5a4422746ed5be3e992f4edb270bcc9a272f7ce0ef284e77a6fc71a，不作为当前23页照片版已逐页检查的声明。

初稿的保守字符数为摘要547，1.1为228、1.2为200、1.3为224、1.4为144、1.5为140、1.6为150，可扩展200、心得517，均在对应模板上限内；9篇参考文献。数值模型、RTL仿真、真实采样、ILA与操作者声音确认的证据边界保留在正文。

## 当前核验入口

```powershell
python -X utf8 scripts/verify_delivery.py --root . --require-vendor
```

上述命令读取本目录的package_manifest.json，核对发布成果、20份RTL对应自检入口、88个固件依赖、当前Word/PDF和全部包文件指纹。验收以实际命令结果为准；历史目录中的日志不冒充本轮重新执行。

## 当前文件指纹

- report/技术文档word版.docx：233b78307b5dad2c41500ebbeae204e3441dbaad657bed3d321c3a6bec2a8299
- report/技术文档pdf版.pdf：880fcc494c6a3d0193e2ed59c7ea212a864e7d07b56a4042eb0fa7909803cfb0
