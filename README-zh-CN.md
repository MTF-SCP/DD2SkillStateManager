# DD2 Skill Controller

[English](README.md) · [中文安装和使用](mod/README-zh-CN.md)

REFramework Lua 武器主动技能管理 Mod，支持觉醒者与主随从同步学习、删除、精确等级设置、按职业批量学习和自动卸下受影响的装备槽。技能编辑仅管理普通主动技能等级；EX 保留游戏武器词条机制。

当前版本 **1.0**：修复职业 / JP 修改被错误回滚的问题，新增一键解锁全部适用职业。当前状态只读显示双方信息，编辑区独立显示所选职业状态；绿色确认、红色放弃 / 锁定和待确认提示更醒目。可选择觉醒者、主随从或双方；字体实时跟随 REFramework 设置。自动读取游戏文字语言，中文显示中文，其他/未知语言显示英文；顶部支持手动选择并保存偏好。职业、技能名称和说明直接读取指定语言的游戏文本。切换界面语言不改变技能等级筛选或写入规则。

## 开发目录

| 路径 | 内容 |
| --- | --- |
| `mod/` | 安装源文件、九个 Lua 文件、字体及许可证、中英说明 |
| `tools/` | 静态检查、打包、参考资料下载和本机部署工具 |
| `docs/` | 架构、语言设计、检查报告及运行时验收状态 |
| `references/` | 来源清单与固定版本哈希；下载的第三方资料仅留本地 |
| `dist/` | 生成的安装 ZIP 和源码 ZIP，不提交 Git |
| `backups/`、`docs/runtime/` | 私有备份与原始报告，不提交 Git |
| `.tools/` | 本地检查依赖，不提交 Git、不成为 Mod 依赖 |

所有开发文件已从父目录迁入 `D:\WorkD\DD2Modding\DD2_SkillController`，迁移时逐文件核验 339 个文件。根目录提供 MIT 许可证和 `.gitignore`。尚未创建或上传 GitHub 仓库；未来上传时以此目录为仓库根，保留忽略规则。安装 ZIP 可另作为 Release 附件上传。

## 静态检查和打包

在项目根目录运行：

```text
python -m pip install --target .tools/python -r tools/requirements-static.txt
python tools/fetch_references.py
python tools/static_check.py
python tools/build.py
```

检查工具只解析/编译 Lua、核验资源和 API，不执行 Mod、模拟游戏环境或完整测试套件。原始用户运行报告仅留本地；没有本机报告时，源码构建仍可以完成语法/绑定/资料核对，报告会明确缺少运行时资料。第三方源码及未取得分发许可的数据不打入发布包，按固定版本清单下载作本地研究。

`deploy_local.py` 要求游戏退出，校验已安装旧版与原源码 ZIP 一致，备份后才更新本 Mod 文件。新增模块只在目标不存在时添加，不覆盖用户文件。`backup_local_saves.py` 只复制本机完整存档目录并核验哈希，不改原存档或云端。

[语言设计](docs/LOCALIZATION.md) · [架构](docs/ARCHITECTURE.md) · [运行时验收](docs/RUNTIME_VALIDATION.md) · [来源](references/SOURCES.md)
