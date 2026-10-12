-- SPDX-License-Identifier: MIT
local access = require("DD2SkillStateManager/access")
local catalog_api = require("DD2SkillStateManager/catalog")
local operations = require("DD2SkillStateManager/operations")
local progress = require("DD2SkillStateManager/progress")
local progress_access = require("DD2SkillStateManager/progress_access")
local M = {}
local sequence = 0
local session = tostring({}):gsub("[^%w]", "")
local base = "DD2SkillStateManager/"

---Serialize portable data only. Empty tables use an explicit marker because this
---REFramework JSON binding encodes them as null, which otherwise loses round-trip keys.
local function portable(value, depth)
    depth = depth or 0
    assert(depth < 32, "诊断结构过深")
    if type(value) ~= "table" then
        assert(type(value) == "string" or type(value) == "number" or type(value) == "boolean",
            "诊断含不可序列化的游戏对象")
        return value
    end
    if next(value) == nil then return {__empty = true} end
    local out = {}
    for key, child in pairs(value) do out[key] = portable(child, depth + 1) end
    return out
end

---Persist and round-trip every byte of logical JSON before reporting a backup as usable.
function M.write(kind, payload)
    local existing = {}
    for _, path in ipairs(fs.glob([[DD2SkillStateManager[/\\].*\.json]])) do
        existing[path:gsub("\\", "/"):lower()] = true
    end
    local path
    repeat
        sequence = sequence + 1
        path = base .. kind .. "_" .. os.date("%Y%m%d_%H%M%S") .. "_" .. session .. "_" .. sequence .. ".json"
    until not existing[path:lower()] -- Reloading twice in one second must not replace an earlier backup.
    local data = portable({schema = 6, mod_version = "1.0", created_at = os.date("%Y-%m-%d %H:%M:%S"),
        empty_table_marker = "{__empty:true}", payload = payload})
    local canonical = json.dump_string(data)
    assert(type(canonical) == "string" and canonical ~= "", "快照 JSON 编码失败")
    assert(json.dump_file(path, data), "无法写入诊断或快照文件")
    local loaded = json.load_file(path)
    assert(loaded and json.dump_string(loaded) == canonical, "快照文件回读不一致；未允许执行技能修改")
    return "reframework/data/" .. path
end

local function capture(destination, key, fn)
    local ok, value = xpcall(fn, debug.traceback)
    destination[key] = ok and {ok = true, value = value} or {ok = false, error = tostring(value)}
end

---Collect partial diagnostics even when catalogue construction or writer contracts fail.
---This routine never invokes a game setter or saves the game.
function M.collect(catalog, status, lock_reason, language)
    local out = {status = status, writer_locked = lock_reason ~= nil, lock_reason = lock_reason,
        verification = "0.1.3 编辑与 0.2.0 自动卸装已有成功日志；1.0 修复职业校验并新增批量解锁；静态检查不替代修复后的游戏验收", types = {}, actors = {}}
    capture(out, "game_language", access.game_language)
    capture(out, "tdb_version", function() return sdk.get_tdb_version() end)
    capture(out, "phase", function()
        local manager = access.singleton("app.MainFlowManager")
        return {current = access.integer(access.call(manager, "get_FlowPhase", {}, nil)),
            in_game = access.in_game()}
    end)
    capture(out, "ownership", function()
        local owned, source = access.expansion_owned()
        return {known = owned ~= nil, owned = owned, source = source}
    end)
    capture(out, "catalogue", function() return catalog_api.export(catalog or catalog_api.build(language)) end)
    local visited = {}
    local function describe_chain(name)
        for _ = 1, 64 do
            if not name or visited[name] then break end
            visited[name] = true
            local ok, description = pcall(access.describe_type, name)
            out.types[#out.types + 1] = ok and description or {name = name, error = tostring(description)}
            name = ok and description.parent or nil
        end
    end
    for _, name in ipairs({"app.HumanSkillContext", "app.HumanSkillContext.EnabledCustomSkill",
        "app.HumanSkillContext.EquipedSkill", "app.HumanSkillContext.EnableNormalSkill", "app.JobContext", "app.JobContext.EquipedArmor",
        "app.Human", "app.HumanStatusContext", "app.IncreaseStatus", "app.AbilityContext",
        "app.AbilityContext.EnableAbility", "app.AbilityContext.EquipedAbility", "System.Int32[]",
        "app.CharacterManager", "app.PawnManager",
        "app.MainFlowManager", "app.GuiManagerBehavior", "app.CustomSkillInformationData",
        "app.CustomSkillSet", "app.CustomSkillInformationParam", "app.GameSystem",
        "app.ExtraContentsManager", "app.GUIBase", "System.Guid", "System.Int32", "System.UInt32",
        "via.gui.message", "via.gui.GUISystem", "via.SceneManager", "via.Scene"}) do
        describe_chain(name)
    end
    -- If an actor accessor mismatches before actor() can finish, its return type is
    -- still discoverable here; users need not manually find every derived class.
    local actor_getters = {get_ManualPlayer = true, get_MainPawn = true, get_CachedCharacter = true,
        get_Human = true, get_SkillContext = true, get_JobContext = true}
    local cursor = 1
    while cursor <= #out.types and cursor <= 128 do
        local description = out.types[cursor]
        for _, method in ipairs(description.methods or {}) do
            if actor_getters[method.name] then describe_chain(method.result) end
        end
        cursor = cursor + 1
    end
    for _, name in ipairs({"app.Character.JobEnum", "app.HumanCustomSkillID",
        "app.HumanCustomSkillLevelNo", "app.HumanSkillContext.SkillSlot", "via.Language", "app.MainFlowManager.Phase"}) do
        local enum_data = {}
        capture(enum_data, "definition", function()
            local values = {}
            for key, value in pairs(access.enum(name).values) do values[#values + 1] = {name = key, value = value} end
            table.sort(values, function(a, b) return a.name < b.name end)
            return values
        end)
        enum_data.name = name
        out.types[#out.types + 1] = enum_data
    end
    for _, role in ipairs({"arisen", "pawn"}) do
        local entry = {role = role}
        capture(entry, "vocation_progress", function()
            return progress.sample(access.actor(role), catalog or catalog_api.build(language))
        end)
        capture(entry, "character_and_augment_guards", function() return progress_access.protected(access.actor(role)) end)
        capture(entry, "state", function()
            local actor = access.actor(role)
            describe_chain(access.type_of(actor.character):get_full_name())
            describe_chain(access.type_of(actor.context):get_full_name())
            describe_chain(access.type_of(access.get(actor.context, "EnabledCustomSkills")):get_full_name())
            return operations.state_export(actor)
        end)
        capture(entry, "writer_contract", function()
            access.writer_contract(access.actor(role))
            return "签名及集合结构匹配；不代表修改行为已经实测"
        end)
        capture(entry, "equipment_contract", function()
            local actor = access.actor(role)
            local none = access.equipment_contract(actor, access.equipment(actor))
            return {none_id = none, native_slots_agree = true}
        end)
        -- Capture equipment/progress independently. A scalar compatibility failure
        -- must not conceal slot references or the type of the failed array element.
        capture(entry, "equipment", function()
            local rows = {}
            for _, row in ipairs(access.equipment(access.actor(role))) do
                rows[#rows + 1] = {job = row.job, slot = row.slot, id = row.id}
            end
            return rows
        end)
        capture(entry, "protected_data_probe", function()
            local actor = access.actor(role)
            local job = access.call(actor.human, "get_JobContext", {}, "app.JobContext")
            local values, experience = {}, {}
            local function scalar(value)
                local row = {lua_type = type(value)}
                if type(value) == "userdata" then
                    local ok, td = pcall(access.type_of, value)
                    if ok then row.managed_type = td:get_full_name(); describe_chain(row.managed_type) end
                end
                capture(row, "integer", function() return access.integer(value) end)
                return row
            end
            for _, name in ipairs({"CurrentJob", "ConsumableExp", "ChangedJobBits", "QualifiedJobBits", "ViewedNewJobBits"}) do
                values[name] = scalar(access.get(job, name))
            end
            local array = access.get(job, "CulmativeExp")
            for i = 0, access.count(array) - 1 do experience[#experience + 1] = scalar(access.item(array, i)) end
            return {fields = values, cumulative_exp = experience}
        end)
        capture(entry, "raw_learning_records", function()
            local actor = access.actor(role)
            local list = access.get(actor.context, "EnabledCustomSkills")
            local rows = {}
            for index = 0, access.count(list) - 1 do
                local record = access.item(list, index)
                local row = {index = index}
                capture(row, "fields", function()
                    local id = access.integer(access.get(record, "CustomSkillID"))
                    local fields = {type = access.type_of(record):get_full_name(), id = id,
                        level = access.integer(access.get(record, "Level")),
                        viewed = access.boolean(access.get(record, "IsViewedNew")),
                        record_enabled = access.boolean(access.call(record, "get_IsEnableProp", {}, "System.Boolean"))}
                    if id > 0 then
                        fields.context_enabled = access.boolean(access.call(actor.context, "isCustomSkillEnable",
                            {"app.HumanCustomSkillID"}, "System.Boolean", id))
                        fields.native_level = access.integer(access.call(actor.context, "getCustomSkillLevel",
                            {"app.HumanCustomSkillID"}, "app.HumanCustomSkillLevelNo", id))
                    end
                    return fields
                end)
                rows[#rows + 1] = row
            end
            return rows -- Duplicate/zero IDs remain visible even when validation rejected them.
        end)
        out.actors[#out.actors + 1] = entry
    end
    capture(out, "qualification_mapping", function()
        local current_catalog = catalog or catalog_api.build(language)
        local sources = {}
        for _, role in ipairs({"arisen", "pawn"}) do
            local ok, data = pcall(function() return progress_access.read(access.actor(role), current_catalog) end)
            if ok then sources[#sources + 1] = {role = role, data = data} end
        end
        return progress_access.mapping(current_catalog, sources)
    end)
    capture(out, "font_api", function()
        return {default_size = imgui.get_default_font_size(), explicit_size_supported = type(imgui.push_font) == "function"}
    end)
    local model = access.learning_model()
    out.learning_model = {valid = model.valid, observations = model.observations, unlearned_level = model.unlearned_level}
    capture(out, "raw_parameters", function()
        local rows = {}
        for _, behavior in ipairs(access.gui_behaviors()) do
            for _, source in ipairs({"CustomSkillInformationData", "ExCustomSkillData"}) do
                local data = access.optional_get(behavior, source)
                if data then
                    local sets = access.get(data, "_Params")
                    for i = 0, access.count(sets) - 1 do
                        local group = access.item(sets, i)
                        if group then
                            local params = access.get(group, "_Params")
                            for j = 0, access.count(params) - 1 do
                                local param = access.item(params, j)
                                if param then
                                    local row = {source = source, job = access.integer(access.get(group, "_Job"))}
                                    capture(row, "fields", function()
                                        return {id = access.integer(access.get(param, "_SkillID")),
                                            level = access.integer(access.get(param, "_Level")),
                                            name = access.message(access.get(param, "_SkillName")),
                                            name_guid = access.guid_text(access.get(param, "_SkillName")),
                                            description_guid = access.guid_text(access.get(param, "_SkillText")),
                                            description = access.message(access.get(param, "_SkillText")),
                                            is_expansion = access.optional_get(param, "_IsExSkill"),
                                            reinforceable = access.optional_get(param, "_Reinforceability"),
                                            open_by_gm = access.optional_get(param, "_OpenByGm"),
                                            rank = access.optional_get(param, "_UnlockRank"),
                                            cost = access.optional_get(param, "_Cost")}
                                    end)
                                    rows[#rows + 1] = row
                                end
                            end
                        end
                    end
                end
            end
        end
        return rows
    end)
    return out
end

return M
