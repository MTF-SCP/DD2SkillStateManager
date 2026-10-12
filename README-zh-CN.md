# DD2 Skill Controller

[English](README.md) · [中文使用指南](mod/README-zh-CN.md)

适用于 **PC Steam 版《Dragon's Dogma 2》** 的 [REFramework](https://github.com/praydog/REFramework) Lua Mod，通过中英文 ImGui 界面管理觉醒者与主随从的武器主动技能、职业资格、职业等级和 JP。

## 功能

- **精确管理技能**：逐项学习、删除或设置有效等级。自动读取游戏技能目录，按职业筛选，支持名称或 ID 搜索。
- **批量学习**：学习当前职业或全部职业的技能，每项采用自身最高可用等级；搜索条件不改变批量范围。
- **自动卸下受影响技能**：删除或变更已装备技能时，自动清空相关槽位，覆盖其他职业保存配置和龙选者引用。
- **职业与 JP 管理**：解锁、锁定职业，设置职业等级，一键解锁全部适用职业，以及设置 JP。支持觉醒者、主随从或双方。
- **预览与确认**：修改前逐项预览；绿色确认、红色放弃。事务保存快照、回读校验，失败时尝试整体恢复。
- **中英本地化**：中文游戏文字设置自动显示中文，其他语言显示英文；支持手动选择并保存，字号实时跟随 REFramework。

编辑范围不包括被动能力、基础技能、人物等级、任务或内容所有权。EX 技能继续由游戏的 DLC 武器词条提供。

## 安装

需要预先安装 REFramework，无需额外运行库。

1. 退出游戏，备份 Steam `userdata/<Steam 数字 ID>/2054970/` 完整目录。
2. 将安装 ZIP 中的 `reframework` 文件夹合并到游戏根目录，与 `DD2.exe` 同级。
3. 也可在 Fluffy Mod Manager 中选择 Dragon's Dogma 2，导入安装 ZIP 并启用。
4. 进入存档，按 Insert，在 **Script Generated UI** 展开 **DD2 技能与职业管理**。

游玩请使用安装包；源码包供开发使用。Lua、中文字体及字体许可证需一起安装。恢复与卸载方法见[中文使用指南](mod/README-zh-CN.md)。

## 使用

**技能页面**：选择职业与技能、设置目标等级，点击“学习 / 设置等级”或“删除技能”。普通职业技能同步双方，觉醒者专属职业仅修改觉醒者；必要角色不可访问时取消操作。受影响技能会自动卸下，修改后需在游戏中重新装备。

**职业与 JP 页面**：“当前状态”始终显示双方信息。在编辑区选择角色范围与职业，分别操作资格、职业等级和 JP。“解锁全部职业”按角色范围处理，跳过主随从不能使用的职业。

所有编辑按钮先生成预览，再点绿色“确认修改”应用。出现“当前保存尚未应用，请确认修改”表示尚未执行。更换选择或点“放弃修改”会撤销预览。修改后按游戏正常方式保存，Mod 不主动触发存档。

## 兼容性与验证

参考环境为游戏 `4.0.0.0`、Steam 构建 `25290080`、REFramework 提交 `d1461375aee4ec3f313170f8eaad12064eb542d9`、TDB 83。接口或结构无法核实时，相应编辑功能会停用。

普通技能编辑和自动卸装已有人工验证。职业 / JP 结构已由导出的运行时数据核对；当前职业 / JP 修改、全部职业解锁及新界面仍待游戏内复核。静态检查不代表游戏行为通过，详见[验证清单](docs/RUNTIME_VALIDATION.md)。

## 开发与构建

使用 Python 3.12，在项目根目录运行：

```powershell
python -m pip install --target .tools/python -r tools/requirements-static.txt
python tools/fetch_references.py
python tools/build.py
```

打包会先执行静态检查，再在 `dist/` 生成安装包、源码包及 `SHA256SUMS.txt`。构建不会启动游戏、执行 Mod 或安装文件。详情见[开发说明](docs/DEVELOPMENT.md)与[贡献指南](CONTRIBUTING.md)。

| 目录 | 内容 |
| --- | --- |
| `mod/` | 可安装 Lua 模块、字体及许可证、中英使用指南 |
| `docs/` | 架构、职业设计、本地化和验证文档 |
| `tools/` | 静态检查、打包、参考资料下载与本地工具 |
| `references/` | 固定版本来源、URL 与 SHA-256 清单 |
| `dist/` | 生成的发布包，不提交 Git |

本地依赖、下载资料、存档备份和原始运行数据不进入 Git 或发布包。

## 许可证与致谢

原创源码使用 [MIT 许可证](LICENSE)。随包 Noto Sans CJK SC 字体使用 SIL OFL 1.1。参考项目、固定版本及许可证见[来源清单](references/SOURCES.md)和[第三方说明](mod/THIRD_PARTY_NOTICES.md)。
