# 参考源码、版本与许可证

获取日期：2026-10-12。哈希、下载 URL、字节数见 `manifest.json` 和 `font-manifest.json`。参考资料保留在本开发目录；除字体及 OFL 外，不进入 Mod 安装包。本文中的项目均仅用于接口和数据结构调查，未嵌入其 Mod 实现。

| 来源 | 固定版本 | 获取内容 | 许可证 |
| --- | --- | --- | --- |
| [praydog/REFramework](https://github.com/praydog/REFramework/tree/d1461375aee4ec3f313170f8eaad12064eb542d9) | d1461375aee4ec3f313170f8eaad12064eb542d9，与本机版本对应 | Sdk.cpp、ImGui.cpp、Json.cpp、FS.cpp、ScriptRunner.cpp、REFramework.cpp | MIT，全文 REFramework/LICENSE |
| [alphazolam/Skill-Maker](https://github.com/alphazolam/Skill-Maker/tree/b9d5d51e369dc19873adfb05eb7967e53388b403) | b9d5d51e369dc19873adfb05eb7967e53388b403 | SkillMaker.lua，角色访问及 REFramework 用法参考 | MIT，全文 Skill-Maker/LICENSE |
| [kagenocookie/dd2-content-editor](https://github.com/kagenocookie/dd2-content-editor/tree/eabf3fc228eecbe5bff8a3a1f0d62384f84e51cd) | eabf3fc228eecbe5bff8a3a1f0d62384f84e51cd | utils.lua，GUID/消息接口参考 | MIT，全文 dd2-content-editor/LICENSE |
| [kagenocookie/REE-Lib-Resources](https://github.com/kagenocookie/REE-Lib-Resources/tree/d40f266c9521eacb3232ebba0e97c9947a888a5b) | d40f266c9521eacb3232ebba0e97c9947a888a5b | resource-info.json、il2cpp_cache.json | MIT，全文 REE-Lib-Resources/LICENSE |
| [REasy/DD2 类型资料](https://github.com/kagenocookie/REasy/blob/103397ac389babfb852558da682e69b44d16fe0c/resources/data/dumps/rszdd2.json) | 103397ac389babfb852558da682e69b44d16fe0c，2026-10-10 更新 | rszdd2.json；用于序列化字段交叉核验 | 该版本根目录 LICENSE 返回 404，未取得许可文本；仅本地调查，不纳入源码/安装 ZIP |
| [notofonts/noto-cjk](https://github.com/notofonts/noto-cjk/tree/f8d157532fbfaeda587e826d4cd5b21a49186f7c) | f8d157532fbfaeda587e826d4cd5b21a49186f7c | 未修改的 NotoSansCJKsc-Regular.otf，改文件名以独立安装 | SIL OFL 1.1，全文随字体发布 |

官方开发文档已经通过网页读取。直接下载网页返回 403，因此未冒称已保存网页源码。实现另以已下载的 C++ Lua 绑定进行版本对应核验：

- [SDK API](https://refdocs.praydog.com/api/sdk.html)：类型/方法/字段反射及原生调用。
- [ImGui API](https://refdocs.praydog.com/api/imgui.html)：combo 返回 Lua 键值；字体路径相对 reframework/fonts。
- [回调接口](https://refdocs.praydog.com/api/re.html)：游戏更新阶段和 UI 回调分工。
- [开发规范](https://refdocs.praydog.com/api/general/best-practices.html)：缓存类型描述，重新取得生命周期不稳定的游戏对象。
- [JSON API](https://refdocs.praydog.com/api/json.html) 和 [文件 API](https://refdocs.praydog.com/api/fs.html)：输出相对 reframework/data。
- [SystemArray](https://refdocs.praydog.com/api/types/SystemArray.html)：元素（含 Int32）是完整 REManagedObject，而非 Lua 数值；0.1.2 据此处理装箱整数。网页已读，未保存 HTML。

本机只读参考：ThePawnController.lua、StartCore/core.lua、Enums_Internal.hpp、REFramework 日志、Steam manifest 和 DD2.exe 的版本属性。未改动这些文件，也未重新分发其源码。它们辅助确认 Native setCustomSkillEnable 使用路径、app.Character.JobEnum 的职业编号、Lv0/Lv1/Lv2 枚举、扩展所有权候选信号、全部职业保存槽结构及当前版本；实际方法签名仍需运行时反射验证。

2026-10-12 补充：用户提供了 0.1.0 的运行时只读诊断（本地开发目录 docs/runtime）。已从其 TDB 83 反射结果确认场景静态 getter、角色上下文路径、记录原生获取属性、技能 getter/setter 及 List 的实际签名；原始用户运行数据不打入发布 ZIP。字段存在与枚举值不能证明获取语义，0.1.1 改用原生获取属性采样确认状态，而非把 Lv0 或预置记录的存在直接当作已学习。

第二次 0.1.1 报告已确认 240 条非哨兵记录的原生获取语义、120 项中文主动目录及 296 条参数。EX 强化复用普通 ID/Lv1，通过独立 `_IsExSkill` 区分；共享职业的 GUID 也可不同。`_Reinforceability` 的字段类型已核实，具体值待 0.1.2 再次采样。原始报告及人物学习状态仅留本地，不重新分发。

第三次 0.1.2 报告已确认强化标记的值、双方完整职业保护数据、各 66 个保存槽，以及 System.Int32 装箱数组读取成功。用户进一步确认 EX 来自 DLC 武器词条，明确无需凭空授予；项目以此作为范围约束，普通等级和武器 EX 资料始终分离。

安装 ZIP 运行时不读取 `references/`。从源码 ZIP 复现静态检查时，先运行 `tools/fetch_references.py` 取得 manifest 中的固定版本资料，再安装检查工具依赖。下载未取得许可的资料仅供本地研究；不会被打包工具重新分发。

0.3.0 语言适配：第三次已导出类型资料确认静态 `via.gui.message.get(Guid, via.Language)` 返回 String，可显式请求语言。REE-Lib 的固定版本枚举资料确认实际拼写 SimplelifiedChinese / TransitionalChinese / English；RSZ 中 via.gui.GUISystem.MessageLanguage 为 native via.Language 属性。现有报告未包含 GUI 语言 getter，其调用必须由本机运行时签名预检，失败回退英文并允许手选。REFramework 对应版本 Sdk.cpp 的 MethodDefinition.call 实现通过 get_real_obj 接受 void* native singleton，语言读取使用准确方法描述，不使用偏移。

0.4.0 职业调查：第三次诊断已反射确认 JobContext 的 calcJobRank(JobEnum)、getJobExp(JobEnum)、getMaxJobRank(JobEnum)、setJobExpWithJobRank(JobEnum, UInt32)、isJobQualified/setJobQualified、ConsumableExp 属性，以及 Human 的 StatusContext/AbilityContext getter。新的人物/成长/被动/武器护甲字段交叉核对固定 RSZ；实际布局和资格位图须由 schema 5 诊断确认。ThePawnController 和 StartCore 的现有本机脚本仅作读法/意图参考，未复制实现或分发。

额外保存对应 REFramework 提交的 [SystemArray.cpp](https://github.com/praydog/REFramework/blob/d1461375aee4ec3f313170f8eaad12064eb542d9/shared/sdk/SystemArray.cpp) 和 SystemArray.hpp，MIT，哈希见 manifest。源码确认 get_element 返回 GetValue 装箱副本、set_element 经 SetValue(Object, Int32) 或受检的类型匹配 Set 路径执行；Lua 数组赋值只能接受托管对象。恢复使用原始 Int32 boxes，运行前验证对应方法存在，不使用自制盒子或内存偏移。

字体显示参考 [官方 ImGui API](https://refdocs.praydog.com/api/imgui.html) 以及本机对应 ImGui.cpp：get_default_font_size 返回框架字号，push_font(font, size) 可以显式指定显示字号。0.4.0 每帧读取字号、字体只加载一次；此接口核对不替代游戏内实际显示验收。

## 1.0 按钮颜色来源

REFramework d1461375aee4ec3f313170f8eaad12064eb542d9 的 dependencies/imgui 子模块指向 [Dear ImGui 85b2fe8486190fa9326565a2fb5fccb6caea4396](https://github.com/ocornut/imgui/tree/85b2fe8486190fa9326565a2fb5fccb6caea4396)，版本 1.92.0。imgui.h 和 MIT LICENSE.txt 原文保存在 references/REFramework，逐文件 URL / 哈希在 manifest.json。该版本没有 Lua ImGuiCol 枚举绑定，故仅使用从头文件核验的 Text=0、Button=21、ButtonHovered=22、ButtonActive=23，静态检查再核对枚举顺序。push_style_color 的整数输入为原生 ABGR，text_colored 为 ARGB；局部样式栈始终恢复。原始头文件及许可证不混入发布 ZIP。
