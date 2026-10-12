"""Static-only release gate. Parse/compile Lua; never execute a Mod chunk or game stub."""
from __future__ import annotations

import hashlib
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.stdout.reconfigure(encoding="utf-8")
sys.path.insert(0, str(ROOT / ".tools/python"))
from luaparser import ast  # noqa: E402
from luaparser.astnodes import Assign, Call, Field, Index, Invoke, Name, String, Table  # noqa: E402
from lupa.lua54 import LuaRuntime  # noqa: E402

MOD = ROOT / "mod"
LUA_ROOT = MOD / "reframework/autorun"
REPORT = ROOT / "docs/STATIC_CHECK_REPORT.md"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def string_value(node):
    if isinstance(node, String):
        return node.s.decode("utf-8") if isinstance(node.s, bytes) else node.s
    if isinstance(node, Name):
        return node.id
    return None


def index_parts(node):
    if isinstance(node, Index) and isinstance(node.value, Name):
        return node.value.id, string_value(node.idx)
    return None, None


def run() -> dict:
    checks, errors, mutation_sites = [], [], []

    def check(label, condition, detail=""):
        checks.append({"label": label, "passed": bool(condition), "detail": detail})
        if not condition:
            errors.append(label + (": " + detail if detail else ""))

    runtime = LuaRuntime(unpack_returned_tuples=True)
    compiler = runtime.eval("function(s,n) local f,e=load(s,n,'t'); return f~=nil,e end")
    trees, texts = {}, {}
    for path in sorted(LUA_ROOT.rglob("*.lua")):
        relative = path.relative_to(MOD).as_posix()
        try:
            raw = path.read_bytes()
            source = raw.decode("utf-8", errors="strict")
            check("UTF-8: " + relative, not raw.startswith(b"\xef\xbb\xbf") and "\ufffd" not in source)
            ok, error = compiler(source, "@" + relative)
            check("Lua 5.4 编译: " + relative, ok, error or "只加载语法，不执行代码")
            trees[path] = ast.parse(source)
            texts[path] = source
            check("Lua AST 解析: " + relative, True)
        except Exception as exc:
            check("Lua 解析: " + relative, False, str(exc))
    check("Lua 文件数量", len(trees) == 9, str(len(trees)))

    sdk_source = (ROOT / "references/REFramework/Sdk.cpp").read_text(encoding="utf-8")
    sources = {
        "sdk": sdk_source,
        "imgui": (ROOT / "references/REFramework/ImGui.cpp").read_text(encoding="utf-8"),
        "json": (ROOT / "references/REFramework/Json.cpp").read_text(encoding="utf-8"),
        "fs": (ROOT / "references/REFramework/FS.cpp").read_text(encoding="utf-8"),
        "re": (ROOT / "references/REFramework/ScriptRunner.cpp").read_text(encoding="utf-8"),
        "log": (ROOT / "references/REFramework/ScriptRunner.cpp").read_text(encoding="utf-8"),
    }
    exports = {
        p.stem: set(re.findall(r"function\s+M\.([A-Za-z_][A-Za-z0-9_]*)\s*\(", text))
        for p, text in texts.items()
    }
    api_used, required, object_methods = set(), set(), set()
    aliases = {"access": "access", "catalog_api": "catalog", "operations": "operations",
               "diagnostics": "diagnostics", "ui": "ui", "i18n": "i18n",
               "progress": "progress", "progress_access": "progress_access"}
    allowed_writers = {"set", "native_grant", "native_set_skill", "remove", "restore", "restore_int_element", "apply", "execute"}
    for path, tree in trees.items():
        relative = path.relative_to(MOD).as_posix()
        for node in ast.walk(tree):
            if isinstance(node, Call):
                if isinstance(node.func, Name) and node.func.id == "require":
                    module = string_value(node.args[0])
                    required.add(module)
                    check("模块引用: " + module, (LUA_ROOT / (module + ".lua")).is_file())
                root, name = index_parts(node.func)
                if root in aliases:
                    check("模块导出: " + root + "." + name, name in exports.get(aliases[root], set()))
                if root in aliases and name in allowed_writers:
                    mutation_sites.append(f"{relative}:{node.first_token.line} {root}.{name}")
                    permitted = (root == "operations" and name == "execute" and path.name == "DD2SkillStateManager.lua")
                    permitted |= (root == "access" and path.name in {"operations.lua", "progress.lua", "progress_access.lua"})
                    permitted |= (root == "progress_access" and path.name == "progress.lua" and name in {"apply", "restore"})
                    check("游戏写入调用层次: " + mutation_sites[-1], permitted)
                if root == "handler" and name == "execute":
                    mutation_sites.append(f"{relative}:{node.first_token.line} handler.execute")
                    check("共享执行入口仅在控制器", path.name == "DD2SkillStateManager.lua")
                if root == "access" and name == "restore_int_element":
                    check("装箱经验写入仅在恢复适配器", path.name == "progress_access.lua")
                if root == "access" and name == "call" and len(node.args) > 1:
                    native_name = string_value(node.args[1])
                    if native_name and native_name in {"setJobQualified", "setJobExpWithJobRank", "set_ConsumableExpProp"}:
                        mutation_sites.append(f"{relative}:{node.first_token.line} native {native_name}")
                        check("职业原生写入仅在适配器", path.name == "progress_access.lua")
                if root == "M" and name in {"set", "native_set_skill", "remove"}:
                    mutation_sites.append(f"{relative}:{node.first_token.line} M.{name}")
                    check("内部恢复写入仅在 access: " + mutation_sites[-1], path.name == "access.lua")
            if isinstance(node, Invoke):
                name = string_value(node.func)
                if name in {"find", "gsub", "lower", "match", "format", "sub"}:
                    continue  # Standard Lua string metatable, not SDK userdata.
                object_methods.add(name)
                check("SDK 对象方法绑定: " + name, f'"{name}"' in sdk_source)
                if name == "set_field":
                    check("直接字段写入仅在 access", path.name == "access.lua")
            # Also inspect callback functions passed to pcall, e.g. pcall(imgui.load_font,...).
            if isinstance(node, Index):
                root, name = index_parts(node)
                if root in sources:
                    api_used.add((root, name))
    for root, name in sorted(api_used):
        check("REFramework 绑定: " + root + "." + name,
              re.search(rf'{root}\["{re.escape(name)}"\]\s*=', sources[root]) is not None
              or re.search(rf'{root}\.new_enum\("{re.escape(name)}"', sources[root]) is not None)
    # Enumerated table flags are registered with new_enum rather than imgui[...].
    for enum, members in (("TableFlags", ("SizingStretchProp", "NoSavedSettings", "RowBg", "BordersInnerH")),
                          ("ColumnFlags", ("WidthFixed", "WidthStretch"))):
        native_enum = "ImGuiTableFlags" if enum == "TableFlags" else "ImGuiTableColumnFlags"
        for member in members:
            check("ImGui 枚举绑定: " + enum + "." + member,
                  f'"{member}", {native_enum}_{member}' in sources["imgui"])
    expected_modules = {"DD2SkillStateManager/" + n for n in ("access", "catalog", "operations", "diagnostics", "ui", "i18n", "progress", "progress_access")}
    check("全部模块可达", required == expected_modules)

    all_lua = "\n".join(texts.values())
    for forbidden in ("write_byte", "write_dword", "write_qword", "write_float", "write_double",
                      "write_short", "sdk.hook", "sdk.create_instance", "os.execute", "io.popen"):
        check("无裸内存/进程入口: " + forbidden, forbidden not in all_lua)
    bootstrap = texts.get(LUA_ROOT / "DD2SkillStateManager.lua", "")
    ui_text = texts.get(LUA_ROOT / "DD2SkillStateManager/ui.lua", "")
    check("唯一更新写入调度", all_lua.count('re.on_pre_application_entry("UpdateBehavior"') == 1)
    check("唯一渲染回调", all_lua.count("re.on_draw_ui(") == 1)
    check("UI 不读写游戏", not any(token in ui_text for token in ("sdk.", "access.", "operations.", "progress_access.")))
    check("修改前强制持久化快照", bootstrap.index('diagnostics.write("before"') < bootstrap.index("handler.execute(final, final_catalog)"))
    check("两类事务共用控制器执行入口", 'local handlers = {skills = operations, progress = progress}' in bootstrap
          and bootstrap.count("handler.execute(") == 1)
    check("安装 font 调用存在", '"DD2SkillStateManager-CJK.otf"' in ui_text)

    # Cross-check serialized fields against the pinned current DD2 dump, not guessed offsets.
    dump = json.loads((ROOT / "references/REasy/rszdd2.json").read_text(encoding="utf-8"))
    types = {v.get("name"): v for v in dump.values()}
    contracts = {
        "app.GuiManagerBehavior": {"CustomSkillInformationData", "ExCustomSkillData"},
        "app.CustomSkillInformationData": {"_Params"},
        "app.CustomSkillSet": {"_Job", "_Params"},
        "app.CustomSkillInformationParam": {"_SkillID", "_Level", "_SkillName", "_SkillText", "_Cost", "_UnlockRank", "_IsExSkill", "_OpenByGm", "_Reinforceability"},
        "app.HumanSkillContext": {"EnabledCustomSkills", "EquipedSkills", "EnableNormalSkills"},
        "app.HumanSkillContext.EnabledCustomSkill": {"CustomSkillID", "Level", "IsViewedNew"},
        "app.HumanSkillContext.EnableNormalSkill": {"NormalSkillID", "IsEnable", "IsViewedNew"},
        "app.HumanSkillContext.EquipedSkill": {"Skills"},
        "app.JobContext": {"CurrentJob", "ConsumableExp", "ChangedJobBits", "QualifiedJobBits", "ViewedNewJobBits", "CulmativeExp"},
        "app.HumanStatusContext": {"_Level", "_Exp", "_IncreaseParams", "_ItemIncreaseWeight", "_AcquiredExtraStatusBoost"},
        "app.AbilityContext": {"EnableAbilities", "EquipedAbilities", "IsAdditionalSlotUnlocked"},
        "app.AbilityContext.EnableAbility": {"AbilityID", "IsEnable", "IsViewedNew"},
        "app.AbilityContext.EquipedAbility": {"Abilities"},
    }
    for name, fields in contracts.items():
        actual = {f["name"] for f in types.get(name, {}).get("fields", [])}
        check("DD2 字段契约: " + name, fields <= actual, ", ".join(sorted(fields - actual)))
    check("学习记录是引用类型", types["app.HumanSkillContext.EnabledCustomSkill"].get("parent") == "System.Object")

    # Real runtime reflection is stronger evidence than serialized field dumps.
    # This is schema/signature comparison against exported data, not game execution.
    candidates = sorted((ROOT / "docs/runtime").glob("diagnostic-*.json"))
    diagnostic = candidates[-1] if candidates else ROOT / "docs/runtime/not-provided.json"
    runtime_signatures = 0
    if diagnostic.is_file():
        native = json.loads(diagnostic.read_text(encoding="utf-8"))["payload"]
        native_types = {item["name"]: item for item in native["types"] if "name" in item}
        native_contracts = [
            ("via.SceneManager", "get_CurrentScene", [], "via.Scene", True),
            ("via.Scene", "findComponents", ["System.Type"], "via.Component[]", False),
            ("app.HumanSkillContext", "setCustomSkillEnable", ["app.HumanCustomSkillID", "app.HumanCustomSkillLevelNo"], "System.Void", False),
            ("app.HumanSkillContext", "isCustomSkillEnable", ["app.HumanCustomSkillID"], "System.Boolean", False),
            ("app.HumanSkillContext", "getCustomSkillLevel", ["app.HumanCustomSkillID"], "app.HumanCustomSkillLevelNo", False),
            ("app.HumanSkillContext", "getSkillID", ["app.Character.JobEnum", "app.HumanSkillContext.SkillSlot"], "app.HumanCustomSkillID", False),
            ("app.HumanSkillContext", "setSkill", ["app.Character.JobEnum", "app.HumanCustomSkillID", "app.HumanSkillContext.SkillSlot"], "System.Boolean", False),
            ("app.HumanSkillContext", "getEquipList", ["app.Character.JobEnum"], "app.HumanSkillContext.EquipedSkill", False),
            ("app.HumanSkillContext.EnabledCustomSkill", "get_IsEnableProp", [], "System.Boolean", False),
            ("app.Human", "get_SkillContext", [], "app.HumanSkillContext", False),
            ("app.Human", "get_JobContext", [], "app.JobContext", False),
            ("app.Human", "get_StatusContext", [], "app.HumanStatusContext", False),
            ("app.Human", "get_AbilityContext", [], "app.AbilityContext", False),
            ("app.JobContext", "calcJobRank", ["app.Character.JobEnum"], "System.UInt32", False),
            ("app.JobContext", "getJobExp", ["app.Character.JobEnum"], "System.Int32", False),
            ("app.JobContext", "get_JobIndex", [], "System.Int32", False),
            ("app.JobContext", "getMaxJobRank", ["app.Character.JobEnum"], "System.Int32", False),
            ("app.JobContext", "setJobExpWithJobRank", ["app.Character.JobEnum", "System.UInt32"], "System.Void", False),
            ("app.JobContext", "get_ConsumableExpProp", [], "System.Int32", False),
            ("app.JobContext", "set_ConsumableExpProp", ["System.Int32"], "System.Void", False),
            ("app.JobContext", "isJobQualified", ["app.Character.JobEnum"], "System.Boolean", False),
            ("app.JobContext", "setJobQualified", ["app.Character.JobEnum"], "System.Void", False),
            ("app.CharacterManager", "get_ManualPlayer", [], "app.Character", False),
            ("app.PawnManager", "get_MainPawn", [], "app.Pawn", False),
            ("app.MainFlowManager", "get_FlowPhase", [], "app.MainFlowManager.Phase", False),
            ("app.GUIBase", "getJobNameMsgID", ["app.Character.JobEnum"], "System.Guid", True),
            ("via.gui.message", "get", ["System.Guid"], "System.String", True),
            ("via.gui.message", "get", ["System.Guid", "via.Language"], "System.String", True),
            ("System.Guid", "ToString", [], "System.String", False),
            ("System.Int32", "ToString", [], "System.String", False),
            ("System.UInt32", "ToString", [], "System.String", False),
        ]
        list_type = "System.Collections.Generic.List`1<app.HumanSkillContext.EnabledCustomSkill>"
        for name, params, ret in (("get_Count", [], "System.Int32"),
                                 ("get_Item", ["System.Int32"], "app.HumanSkillContext.EnabledCustomSkill"),
                                 ("RemoveAt", ["System.Int32"], "System.Void"),
                                 ("Insert", ["System.Int32", "app.HumanSkillContext.EnabledCustomSkill"], "System.Void")):
            native_contracts.append((list_type, name, params, ret, False))
        for owner, name, params, ret, static in native_contracts:
            methods = native_types.get(owner, {}).get("methods", [])
            matches = [m for m in methods if m["name"] == name
                       and (m["parameters"] if isinstance(m["parameters"], list) else []) == params
                       and m["result"] == ret and m["static"] == static]
            check("运行时签名资料核对: " + owner + "." + name, len(matches) == 1)
            runtime_signatures += 1
        for name in ("IsAllSkillEnable", "IsNormalSkillEnable"):
            fields = native_types["app.HumanSkillContext"]["fields"]
            check("原生保护字段: " + name, any(f["name"] == name and f["type"] == "System.Boolean" and not f["static"] for f in fields))
        if "learning_model" in native:
            model = native["learning_model"]
            check("导出资料的获取语义已核验", model.get("valid") is True
                  and model.get("unlearned_level") == 0
                  and {row["level"]: row["learned"] for row in model["observations"]} == {0: False, 1: True, 2: True},
                  "仅核对已导出的本机资料；不作为跨版本硬编码或修改行为测试")
        for actor in native.get("actors", []):
            data = actor.get("raw_learning_records", {})
            if data.get("ok"):
                rows = [r["fields"]["value"] for r in data["value"] if r["fields"].get("ok") and r["fields"]["value"]["id"] > 0]
                check("导出原生记录一致: " + actor["role"], bool(rows) and all(
                    r["record_enabled"] == r["context_enabled"] and r["level"] == r["native_level"] for r in rows),
                    f"{len(rows)} 条实际已导出记录；未执行任何 getter/setter")
            state = actor.get("state", {})
            if state.get("ok"):
                value = state["value"]
                check("完整角色状态已读出: " + actor["role"],
                      isinstance(value.get("equipment"), list) and bool(value["equipment"])
                      and bool(value.get("protected_progress", {}).get("job", {}).get("cumulative_exp")),
                      "仅检查已有报告；不替代修改验收")
            probe = actor.get("protected_data_probe", {})
            if probe.get("ok"):
                experience = probe["value"]["cumulative_exp"]
                check("已有装箱经验采样: " + actor["role"], bool(experience)
                      and all(x.get("managed_type") == "System.Int32" and x["integer"].get("ok") for x in experience))
            vocation = actor.get("vocation_progress", {})
            if vocation.get("ok"):
                value = vocation["value"]
                data = value.get("data", {})
                check("完整职业保护与恢复已读出: " + actor["role"], value.get("protected_ok") is True
                      and all(data.get("capabilities", {}).get(k, {}).get("ok") for k in ("jp", "rank", "qualification", "recovery")))
                check("原生职业经验与记录逐项一致: " + actor["role"], all(
                    row.get("rank_ok") and row["exp"] == data["experience"][row["index"]]
                    and 1 <= row["rank"] <= row["maximum"] for row in data.get("jobs", [])))
                check("人物/被动/武器护甲保护完整读出: " + actor["role"],
                      actor.get("character_and_augment_guards", {}).get("ok") is True)
        for name in ("_IsExSkill", "_Reinforceability"):
            fields = native_types.get("app.CustomSkillInformationParam", {}).get("fields", [])
            check("原生目录区分字段: " + name, any(f["name"] == name and f["type"] == "System.Boolean" and not f["static"] for f in fields))
    access_text = texts.get(LUA_ROOT / "DD2SkillStateManager/access.lua", "")
    operation_text = texts.get(LUA_ROOT / "DD2SkillStateManager/operations.lua", "")
    progress_text = texts.get(LUA_ROOT / "DD2SkillStateManager/progress.lua", "")
    adapter_text = texts.get(LUA_ROOT / "DD2SkillStateManager/progress_access.lua", "")
    for name in ("specification", "prepare", "backup", "execute"):
        check("共享事务模块接口: " + name, name in exports["operations"] and name in exports["progress"])
    check("职业锁定采用唯一映射且不锁当前职业", 'assert(mapping.known' in progress_text
          and 'data.fields.CurrentJob ~= spec.job_id' in progress_text and 'assert(not row.basic' in progress_text)
    check("JP 和等级请求分别验证整数", 'value <= 2147483647' in progress_text
          and 'value >= 1' in progress_text and 'spec.value <= row.maximum' in progress_text)
    check("同级保留原始经验", 'writes = before ~= after' in progress_text
          and 'if change.writes then' in progress_text and 'progress_access.apply(state.data, kind' in progress_text)
    check("职业差异白名单不包含旧职业指纹", 'state.protected_progress.job = nil' in progress_text
          and 'state.protected_progress.fingerprint = nil' in progress_text
          and 'difference(state.guard, current_guard' in progress_text)
    check("批量职业解锁仅修改资格并复用事务", 'vocation_unlock_all = true' in progress_text
          and 'for _, id in ipairs(catalog.job_order)' in progress_text
          and 'role == "pawn" and policy == "arisen"' in progress_text
          and 'added == qualification_count' in progress_text and 'delta == qualification_mask' in progress_text
          and 'prepared.spec.kind == "vocation_unlock_all" and "vocation_unlock"' in progress_text)
    check("批量资格之外经验及历史完整核验", 'now.experience[index] == value' in progress_text
          and 'else assert(now.fields[name] == value' in progress_text and 'b.qualified == a.qualified' in progress_text)
    check("逐项预览角色来自请求且窄布局保留职业名", 'return {role = item.role, field =' in progress_text
          and ui_text.count('preview_label(state, item, row)') == 3)
    check("当前状态双角色只读且编辑另列", 'local function current_progress(state)' in ui_text
          and 'ipairs({"arisen", "pawn"})' in ui_text
          and ui_text.index('current_progress(state)', ui_text.index('local function progress_contents')) < ui_text.index('heading("vocation_edit")')
          and 'DD2SSMSelectedVocation' in ui_text and 'heading("jp_edit")' in ui_text)
    check("待确认提示顶端及确认区同时显示", ui_text.count('text(t("pending_confirmation"), nil, warning)') == 2
          and 'button("confirm", "DD2SSMExecute", "confirm")' in ui_text
          and 'button("cancel", "DD2SSMCancel", "danger")' in ui_text)
    header = (ROOT / "references/REFramework/imgui.h").read_text(encoding="utf-8")
    color_body = re.search(r'enum ImGuiCol_\s*\{(.*?)\n\};', header, re.S).group(1)
    color_names = re.findall(r'^\s*(ImGuiCol_\w+)\s*[,=]', color_body, re.M)
    check("按钮颜色常量核对框架实际 ImGui 版本", 'style_colors = {text = 0, button = 21, hovered = 22, active = 23}' in ui_text
          and [color_names.index('ImGuiCol_' + n) for n in ('Text', 'Button', 'ButtonHovered', 'ButtonActive')] == [0, 21, 22, 23]
          and 'imgui.pop_style_color(count)' in ui_text and 'color - 0x100000000' in ui_text)
    check("角色等级和被动能力完整保护", all(x in adapter_text for x in ('"get_StatusContext"', '"get_AbilityContext"',
          '"_IncreaseParams"', '"EnableAbilities"', '"EquipedAbilities"')) and 'state.guard_fingerprint' in progress_text)
    check("恢复精确经验且装箱值没有裸内存写入", 'progress_access.restore(state.actor, state.data)' in progress_text
          and 'access.restore_int_element(data.array, index - 1, data.boxes[index])' in adapter_text
          and 'array[index] = boxed' in access_text and 'value.is<REManagedObject*>()' in sdk_source)
    array_source = (ROOT / "references/REFramework/SystemArray.cpp").read_text(encoding="utf-8")
    check("SystemArray 对应版本实际装箱恢复实现", 'SetValue(System.Object, System.Int32)' in array_source
          and 'GetValue(System.Int32)' in array_source and 'case 4:' in array_source
          and 'M.int_array_contract(array)' in access_text and 'data.capabilities.recovery.ok' in progress_text)
    check("职业解锁不改首次转职历史", '"setJobChanged"' not in adapter_text and '"setJobViewedNew"' not in adapter_text)
    check("字体实时跟随框架且只加载一次", 'pcall(imgui.get_default_font_size)' in ui_text
          and 'imgui.push_font(font, size)' in ui_text and 'if not font_attempted then' in ui_text
          and '"DD2SkillStateManager-CJK.otf", 20' not in ui_text)
    check("大字号预览和列宽使用当前测量", 'imgui.calc_text_size(preview_change' in ui_text
          and 'local compact = available <' in ui_text and 'ui.glyph_widths' in ui_text)
    check("原生场景静态契约", '"get_CurrentScene", {}, "via.Scene", true' in access_text)
    check("获取状态采用原生属性", '"get_IsEnableProp"' in access_text and '"isCustomSkillEnable"' in access_text)
    check("预置行不因正常删除被移除", "access.remove(" not in operation_text)
    check("包含 ID 0 哨兵但禁止负 ID", "assert(id >= 0 and not map[id]" in access_text)
    check("未获取等级由原生观察核验", "unlearned_level" in access_text and "grade_conflict" in access_text)
    catalog_text = texts.get(LUA_ROOT / "DD2SkillStateManager/catalog.lua", "")
    check("装箱整数按类型与反射方法读取", all(t in access_text for t in ('["System.Int32"]', '["System.UInt32"]', '"ToString", {}, "System.String", false')))
    check("EX 强化不混入普通保存等级", "marked_ex == true and skill.ex_variants or skill.variants" in catalog_text)
    check("有效等级还需强化和占位筛查", all(t in catalog_text for t in ('"_Reinforceability"', "skill.selectable[level]", "excluded_levels", "description_guid")))
    check("跨职业本地化独立保存", "merge_variant" in catalog_text and "candidate.job == origin_job" in catalog_text)
    check("界面不渲染技术堆栈和开发说明", all(t not in ui_text for t in (
        "text(state.status)", "text(sample.error)", "text(skill.reason)", "text(state.last_file)",
        "当前未实现", "尚未实测", "等级筛选说明", "武器 EX 强化说明", "诊断详情")))
    check("EX 独立保留且没有授予入口", "variants = marked_ex == true and skill.ex_variants or skill.variants" in catalog_text
          and "skill.ex_variants" not in ui_text)
    check("原生空技能枚举不猜测", 'M.enum("app.HumanCustomSkillID").values.None' in access_text)
    check("槽位写入不用数组绕过游戏", "row.array[row.slot] =" not in access_text
          and '"setSkill", {"app.Character.JobEnum"' in access_text)
    check("自动卸装逐槽预览", "state.expected_equipment[index].id = state.none_id" in operation_text
          and "unequips = prepared.unequips" in bootstrap and "item.actual_slot_writes" in ui_text)
    check("先卸装核验再改学习状态", operation_text.index("access.native_set_skill(state.actor")
          < operation_text.index("verify_state(state, false, true)") < operation_text.index("apply(state)\n", operation_text.index("function M.execute")))
    check("回滚通过原生接口恢复装备", "M.native_set_skill(actor, row.job, row.slot, row.id)" in access_text)
    check("校验学习状态及指定槽位以外的差异", "verify_equipment(rollback and state.equipment or state.expected_equipment" in operation_text
          and "access.equipment_contract(state.actor, equipment)" in operation_text)
    check("单独清除异常装备槽不会被无操作分支吞掉", "prepared.actual_writes + prepared.actual_slot_writes == 0" in bootstrap
          and "prepared.actual_writes + prepared.actual_slot_writes == 0" in operation_text)
    check("同级无操作不卸装", "if writes or not change.learned then" in operation_text)
    check("换选择取消旧确认", "state.preview = nil -- Never leave a confirmation" in ui_text)
    check("未解析升级说明不参与授予", 'variant.validation_description == ""' in catalog_text)
    check("原生等级独立核验", "record.native_level" in access_text and "actual.native_level == record.level" in operation_text)
    check("批量学习不降低原始等级", "bulk and before and before.enabled and change.level < before.level" in operation_text)

    # Inspect literal localization tables/format strings with the AST only. Do not
    # require/execute Lua or simulate game/UI callbacks to validate translations.
    locale_path = LUA_ROOT / "DD2SkillStateManager/i18n.lua"
    locale_text = texts.get(locale_path, "")
    dictionaries = {}
    for node in ast.walk(trees[locale_path]):
        if isinstance(node, Assign) and index_parts(node.targets[0]) == ("M", "strings"):
            table_node = node.values[0]
            check("语言资源是静态字典", isinstance(table_node, Table))
            for language_field in table_node.fields:
                language = string_value(language_field.key)
                dictionaries[language] = {string_value(f.key): string_value(f.value) for f in language_field.value.fields}
    check("仅中英文资源", set(dictionaries) == {"en", "zh"})
    english, chinese = dictionaries.get("en", {}), dictionaries.get("zh", {})
    check("中英资源键完整一致", bool(english) and set(english) == set(chinese))
    for key, value in english.items():
        check("英文文本无中文残留: " + key, isinstance(value, str) and re.search(r"[\u4e00-\u9fff]", value) is None)
        check("中英格式参数一致: " + key, re.findall(r"%[ds]", value) == re.findall(r"%[ds]", chinese.get(key, "")))
    referenced = {"arisen", "pawn"}
    for node in ast.walk(trees[LUA_ROOT / "DD2SkillStateManager/ui.lua"]):
        if isinstance(node, Call) and isinstance(node.func, Name) and node.func.id in {"t", "widget", "heading"}:
            if node.args and isinstance(node.args[0], String): referenced.add(string_value(node.args[0]))
    for path in (LUA_ROOT / "DD2SkillStateManager.lua", LUA_ROOT / "DD2SkillStateManager/ui.lua"):
        for node in ast.walk(trees[path]):
            if isinstance(node, Field) and string_value(node.key) == "key":
                referenced.update(string_value(n) for n in ast.walk(node.value) if isinstance(n, String))
    check("界面和状态所引用语言键存在", referenced <= set(english), ", ".join(sorted(referenced - set(english))))
    check("语言资源不访问游戏", not any(t in locale_text for t in ("sdk.", "access.", "operations.", "re.", "imgui.")))
    check("其他及未知语言回退英文", 'game_name == "SimplelifiedChinese" or game_name == "TransitionalChinese"' in locale_text
          and 'return "en"' in locale_text)
    enum_data = json.loads((ROOT / "references/REE-Lib-Resources/il2cpp_cache.json").read_text(encoding="utf-8"))
    language_names = {entry["name"] for entry in enum_data["Enums"]["via.Language"]["Items"]}
    check("语言名称核对资料枚举，不使用数字猜测", {"English", "SimplelifiedChinese", "TransitionalChinese"} <= language_names)
    check("自动识别文字语言并可手动回退", all(t in access_text for t in ('"get_MessageLanguage"', 'sdk.get_native_singleton("via.gui.GUISystem")'))
          and 'kind = "language"' in ui_text and '"auto", "zh", "en"' in ui_text)
    check("显式中英游戏文本，不改变游戏语言", '{"System.Guid", "via.Language"}' in access_text
          and 'access.message(name_guid, result.language)' in catalog_text
          and 'access.job_name(id, result.language)' in catalog_text and 'set_MessageLanguage' not in all_lua)
    check("显示翻译不控制有效等级", 'validation_description = access.message(description_id)' in catalog_text
          and 'variant.validation_description == ""' in catalog_text)
    check("语言偏好即时保存且不在退出回调中写", '"DD2SkillStateManager/settings.json"' in bootstrap
          and 'language_mode = request.mode' in bootstrap and 're.on_script_reset' not in bootstrap)
    check("翻译控件 ID 不随语言改变", 't(key) .. "###" .. id' in ui_text)
    ignore = (ROOT / ".gitignore").read_text(encoding="utf-8")
    check("GitHub 忽略存档、运行时数据和下载资料", all(p in ignore.splitlines() for p in (
        ".tools/", "backups/", "dist/", "docs/runtime/", "references/*", "!references/manifest.json")))
    check("仓库根许可证与 Mod 一致", (ROOT / "LICENSE").read_bytes() == (MOD / "LICENSE").read_bytes())

    allowed_extensions = {".lua", ".md", ".ini", ".txt", ".otf"}
    hashes = {}
    for path in sorted(MOD.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(MOD).as_posix()
        check("安装树仅含运行文件/说明: " + relative,
              path.suffix in allowed_extensions or path.name == "LICENSE")
        check("安装树无用户状态: " + relative, "reframework/data/" not in relative)
        if path.suffix != ".otf":
            try:
                text = path.read_bytes().decode("utf-8", errors="strict")
                check("安装文本 UTF-8: " + relative, "\ufffd" not in text)
            except UnicodeError as exc:
                check("安装文本 UTF-8: " + relative, False, str(exc))
        if path.name != "STATIC_CHECK_REPORT.md":
            hashes[relative] = sha(path)  # Generated report is hashed by the package manifest.
    for record in json.loads((ROOT / "references/font-manifest.json").read_text(encoding="utf-8")):
        check("字体及许可证哈希: " + record["path"], sha(ROOT / record["path"]) == record["sha256"])
    reference_verified = 0
    for record in json.loads((ROOT / "references/manifest.json").read_text(encoding="utf-8")):
        if "sha256" not in record:
            continue
        path = ROOT / record["path"]
        check("参考源码哈希: " + record["path"], path.is_file() and sha(path) == record["sha256"])
        reference_verified += 1
    check("许可证与元数据齐全", all((MOD / p).is_file() for p in ("LICENSE", "modinfo.ini", "THIRD_PARTY_NOTICES.md", "README-zh-CN.md")))

    result = {"created_at": datetime.now(timezone.utc).isoformat(), "passed": not errors,
              "lua_version": runtime.lua_version, "lua_files": len(trees), "checks": checks,
              "errors": errors, "mutation_sites": mutation_sites, "file_hashes": hashes,
              "runtime_verified": False, "reference_files_verified": reference_verified}
    result["runtime_signatures_checked"] = runtime_signatures
    (ROOT / "docs").mkdir(exist_ok=True)
    (ROOT / "docs/static-results.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    lines = ["# 静态检查报告", "", "结果：" + ("通过" if not errors else "失败"), "",
             f"检查时间（UTC）：{result['created_at']}。Lua 5.4 编译器 + luaparser AST；共 {len(checks)} 项检查，{len(errors)} 项失败。",
             "", "检查只加载、解析源码，未执行 Mod、原生游戏方法、模拟测试或完整测试套件。", "",
             "| 范围 | 结果 |", "| --- | --- |",
             f"| {len(trees)} 个 Lua 文件：UTF-8、Lua 5.4 编译、AST 解析 | {'通过' if not errors else '见失败项'} |",
             "| 模块引用和导出、回调、REFramework API/对象方法与已安装源码版本核对 | 见逐项 JSON 结果 |",
             "| DD2 序列化字段与 2026-10-10 类型资料核对 | 见逐项 JSON 结果 |",
             f"| 最新已导出报告的 {runtime_signatures} 个实际方法签名与新契约核对 | {'通过' if runtime_signatures else '未提供本机原始报告'} |",
             "| 游戏写入入口分层、UI 无游戏访问、快照先于事务 | 见逐项 JSON 结果 |",
             "| 字体/OFL、参考源码哈希、安装树、文本编码、许可证与元数据 | 见逐项 JSON 结果 |",
             "| 0.1.3 普通编辑 | 用户已确认生效；四份成功日志见运行时报告 |",
             "| 0.2.0 已装备删除与重新获取 | 新日志确认成功自动卸下一槽并同步修改 |",
             "| 0.3.0 中英界面与游戏文本、自动识别 | 静态字典/API核对；实际显示待进游戏确认 |",
             "| 1.0 职业资格、等级、JP、批量解锁与界面 | 0.4.0 新诊断确认完整结构；误回滚已修复；修改后行为待游戏复核 |", "",
             "## 写入入口审查", "", *["- `" + site + "`" for site in mutation_sites], "",
             "技能写入集中在 access 与技能事务；职业/JP 原生写入和资格单个位写入集中在 progress_access，控制器只有一个共享执行入口。装箱 Int32 数组仅在异常恢复中赋值，不能用 Lua 数字或裸偏移写入。职业操作保护人物等级、成长属性、被动能力及技能装备；首次转职历史、任务和内容所有权不主动修改。", "",
             "## 限制", "",
             "静态 API 核对确认符号在所调查 REFramework 绑定中存在，不证明任意游戏对象均可调用，也不证明游戏 TDB 中方法返回类型。真实签名由运行时预检和诊断提供。字段资料为序列化结构，不能替代运行时集合签名。", "",
             "三次只读报告确认本机获取语义及完整状态；0.1.3 的四份成功日志和 0.2.0 的两份新成功日志已留存。后者确认主随从一槽自动卸下及双方删除/重新学习。显式 get(Guid, via.Language) 已从现有反射资料核对；自动 GUI 文字语言 getter 在运行时按签名预检，不可用时回退英文并允许手选。中英资源、格式参数及引用仅作 AST 静态检查，没有执行 Lua、游戏或模拟测试。本轮语言显示、保存偏好和自动检测仍需实际显示确认；恢复失败/保存重启等未覆盖场景仍见运行时报告。", "",
             "ZIP 文件树、压缩流及包内哈希检查由打包工具单独写入 PACKAGE_CHECK_REPORT.md。源码的完整逐项结果与哈希见 static-results.json。"]
    if errors:
        lines += ["", "## 失败项", "", *["- " + error for error in errors]]
    REPORT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(json.dumps({"passed": not errors, "checks": len(checks), "errors": errors,
                      "report": str(REPORT)}, ensure_ascii=False))
    return result


if __name__ == "__main__":
    sys.exit(0 if run()["passed"] else 1)
