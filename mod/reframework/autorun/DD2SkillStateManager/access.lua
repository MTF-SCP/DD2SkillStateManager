-- SPDX-License-Identifier: MIT
-- Typed access to DD2 objects. Missing/ambiguous contracts are errors, never empty state.
local M = {}
local method_cache, field_cache, enum_cache = {}, {}, {}
local RECORD = "app.HumanSkillContext.EnabledCustomSkill"
local grade_states, grade_conflict = {}, false

---Convert an SDK enum/scalar without interpreting a managed-object address as a value.
---@param value any
---@return integer
function M.integer(value)
    if type(value) == "number" and math.tointeger(value) then return math.tointeger(value) end
    if type(value) == "userdata" then
        local ok, boxed = pcall(function() return value:get_field("value__") end)
        if ok and type(boxed) == "number" then return M.integer(boxed) end
        -- SystemArray.get_element returns managed boxes even for Int32[] (official
        -- SystemArray contract). Unbox through the exact primitive ToString method;
        -- never reinterpret its heap address or assume a payload memory offset.
        local primitive_ok, primitive = pcall(function()
            local td = value:get_type_definition()
            local name = td:get_full_name()
            local limits = { ["System.Int32"] = {-2147483648, 2147483647},
                ["System.UInt32"] = {0, 4294967295} }
            local range = assert(limits[name], "不是支持的装箱整数类型")
            local text = M.method(td, "ToString", {}, "System.String", false):call(value)
            assert(type(text) == "string" and text:match("^%-?%d+$"), "装箱整数文本格式异常")
            local number = math.tointeger(tonumber(text))
            assert(number and number >= range[1] and number <= range[2], "装箱整数越界")
            return number
        end)
        if primitive_ok then return primitive end
        local converted, bits = pcall(sdk.to_int64, value)
        if converted and type(bits) == "number" and bits >= 0 and bits <= 0xFFFFFFFF then
            if bits >= 0x80000000 then bits = bits - 0x100000000 end
            return math.tointeger(bits)
        end
    end
    error("无法解析整数或枚举值: " .. tostring(value))
end

function M.boolean(value)
    if type(value) == "boolean" then return value end
    local n = M.integer(value)
    if n == 0 then return false elseif n == 1 then return true end
    error("布尔字段不是 0/1")
end

function M.type_of(object)
    assert(object ~= nil, "游戏对象不可用")
    return assert(object:get_type_definition(), "无法读取对象类型")
end

function M.address(object)
    return object and tostring(object:get_address()) or "nil"
end

local function exact_params(method, expected)
    if method:get_num_params() ~= #expected then return false end
    local actual = method:get_param_types()
    for i, name in ipairs(expected) do
        if not actual[i] or actual[i]:get_full_name() ~= name then return false end
    end
    return true
end

---Resolve a unique reflected method, including parameter types, return type and staticness.
---@param td userdata
---@param name string
---@param params string[]
---@param result string|nil
---@param is_static boolean
---@return userdata
function M.method(td, name, params, result, is_static)
    assert(td, "缺少游戏类型")
    local key = td:get_full_name() .. "|" .. name .. "|" .. table.concat(params, ",")
        .. "|" .. tostring(result) .. "|" .. tostring(is_static)
    if method_cache[key] then return method_cache[key] end
    local found, owner = nil, td
    -- Search the nearest declaring type first. Character accessors can be inherited;
    -- enumerating only Pawn/Human methods would incorrectly reject a valid contract.
    for _ = 1, 64 do
        if not owner then break end
        for _, method in ipairs(owner:get_methods()) do
            if method:get_name() == name and method:is_static() == is_static and exact_params(method, params)
                and (not result or method:get_return_type():get_full_name() == result) then
                assert(not found, "方法签名不唯一: " .. key)
                found = method
            end
        end
        if found then break end
        owner = owner:get_parent_type()
    end
    assert(found, "缺少已核验签名: " .. key)
    method_cache[key] = found
    return found
end

function M.call(object, name, params, result, ...)
    return M.method(M.type_of(object), name, params, result, false):call(object, ...)
end

function M.get(object, name)
    local td = M.type_of(object)
    local key = td:get_full_name() .. "|" .. name
    local field = field_cache[key]
    local owner = td
    for _ = 1, 64 do
        if field or not owner then break end
        field = owner:get_field(name)
        owner = owner:get_parent_type()
    end
    assert(field and not field:is_static(), "缺少实例字段: " .. key)
    field_cache[key] = field
    return field:get_data(object)
end

---Set an existing typed field. All calls are confined to transaction/rollback code.
function M.set(object, name, value)
    M.get(object, name) -- Validate existence before asking the SDK to write.
    object:set_field(name, value)
end

---Preflight the exact native setter used by REFramework's checked array assignment.
---@return string setter_name
function M.int_array_contract(array)
    local td = M.type_of(array)
    assert(td:get_full_name() == "System.Int32[]", "恢复数组类型不匹配")
    local ok = pcall(M.method, td, "SetValue", {"System.Object", "System.Int32"}, "System.Void", false)
    if ok then return "SetValue" end
    M.method(td, "Set", {"System.Int32", "System.Int32"}, "System.Void", false)
    return "Set"
end

---Restore an original boxed Int32, not a Lua number, through the validated setter.
---Only the vocation recovery adapter may call this function; no payload offset is used.
function M.restore_int_element(array, index, boxed)
    M.int_array_contract(array)
    assert(M.type_of(array):get_full_name() == "System.Int32[]", "恢复数组类型不匹配")
    assert(M.type_of(boxed):get_full_name() == "System.Int32", "恢复经验不是装箱 Int32")
    assert(index >= 0 and index < M.count(array), "恢复经验下标越界")
    local expected = M.integer(boxed)
    array[index] = boxed
    assert(M.integer(M.item(array, index)) == expected, "恢复职业经验回读不匹配")
end

function M.optional_get(object, name)
    local ok, result = pcall(M.get, object, name)
    if ok then return result end
    return nil
end

---Validate writable storage independently from native method signatures.
function M.field_contract(object, name, expected)
    M.get(object, name)
    local field = field_cache[M.type_of(object):get_full_name() .. "|" .. name]
    assert(field and field:get_type():get_full_name() == expected, "字段存储类型变化: " .. name)
end

function M.enum(name)
    if enum_cache[name] then return enum_cache[name] end
    local td = assert(sdk.find_type_definition(name), "缺少枚举: " .. name)
    assert(td:is_enum(), "类型不是枚举: " .. name)
    local values, names = {}, {}
    for _, field in ipairs(td:get_fields()) do
        if field:is_static() then
            local value = M.integer(field:get_data(nil))
            values[field:get_name()] = value
            names[value] = field:get_name()
        end
    end
    enum_cache[name] = {values = values, names = names}
    return enum_cache[name]
end

---Arrays and List<T> share a bounded read interface; unsupported shapes fail closed.
function M.count(collection)
    local td = M.type_of(collection)
    local n
    if td:is_array() then n = M.integer(collection:get_size())
    else n = M.integer(M.call(collection, "get_Count", {}, "System.Int32")) end
    assert(n >= 0 and n <= 8192, "集合长度异常: " .. tostring(n))
    return n
end

function M.item(collection, index)
    assert(index >= 0 and index < M.count(collection), "集合下标越界")
    if M.type_of(collection):is_array() then return collection:get_element(index) end
    return M.call(collection, "get_Item", {"System.Int32"}, nil, index)
end

function M.singleton(name)
    return assert(sdk.get_managed_singleton(name), "单例尚不可用: " .. name)
end

function M.scene()
    local td = assert(sdk.find_type_definition("via.SceneManager"))
    -- Confirmed by the 2026-10-12 runtime report: this getter is static in TDB 83.
    return assert(M.method(td, "get_CurrentScene", {}, "via.Scene", true):call(nil), "当前场景尚不可用")
end

function M.in_game()
    local ok, result = pcall(function()
        local phase = M.integer(M.call(M.singleton("app.MainFlowManager"), "get_FlowPhase", {},
            "app.MainFlowManager.Phase"))
        return phase == M.enum("app.MainFlowManager.Phase").values.InGame
    end)
    return ok and result == true
end

---Find catalogue-owning components only when rebuilding the catalogue, never every frame.
function M.gui_behaviors()
    local list = M.call(M.scene(), "findComponents", {"System.Type"}, nil,
        sdk.typeof("app.GuiManagerBehavior"))
    local found = {}
    for i = 0, M.count(list) - 1 do
        local object = M.item(list, i)
        if object then found[#found + 1] = object end
    end
    assert(#found > 0, "未找到 app.GuiManagerBehavior；请进入存档后刷新目录")
    return found
end

function M.actor(role)
    local character
    if role == "arisen" then
        character = M.call(M.singleton("app.CharacterManager"), "get_ManualPlayer", {}, nil)
    else
        local pawn = M.call(M.singleton("app.PawnManager"), "get_MainPawn", {}, nil)
        assert(pawn, "主随从当前不可访问")
        character = M.call(pawn, "get_CachedCharacter", {}, nil)
    end
    assert(character, role == "arisen" and "觉醒者当前不可访问" or "主随从尚未载入")
    local human = assert(M.call(character, "get_Human", {}, "app.Human"), "Human 当前不可用")
    local context = assert(M.call(human, "get_SkillContext", {}, "app.HumanSkillContext"))
    local id = M.integer(M.call(character, "get_CharaID", {}, "app.CharacterID"))
    return {role = role, character = character, human = human, context = context,
        identity = tostring(id) .. ":" .. M.address(human) .. ":" .. M.address(context)}
end

---An absent ownership signal is unknown, not permission to grant expansion skills.
function M.expansion_owned()
    local ok, result = pcall(function()
        return M.boolean(M.get(M.singleton("app.GameSystem"), "<HasContents0014>k__BackingField"))
    end)
    if ok then return result, "GameSystem.HasContents0014" end
    ok, result = pcall(function()
        return M.boolean(M.get(M.singleton("app.ExtraContentsManager"), "IsRegistedContents0014"))
    end)
    if ok then return result, "ExtraContentsManager.IsRegistedContents0014" end
    return nil, "内容所有权接口未核验"
end

---Read only the game's UI text language; failures are optional and default to English.
---Use a typed native property, not voice language, OS settings or numeric enum guesses.
function M.game_language()
    local ok, result = pcall(function()
        local td = assert(sdk.find_type_definition("via.gui.GUISystem"), "缺少 GUI 系统类型")
        local getter = M.method(td, "get_MessageLanguage", {}, "via.Language", false)
        local system = assert(sdk.get_native_singleton("via.gui.GUISystem"), "GUI 系统尚未载入")
        -- MethodDefinition.call accepts a native pointer in the pinned SDK binding;
        -- call the exact descriptor rather than selecting an overload by name again.
        local value = M.integer(getter:call(system))
        local name = assert(M.enum("via.Language").names[value], "未知文字语言枚举")
        return {known = true, name = name, value = value, source = "via.gui.GUISystem.MessageLanguage"}
    end)
    if ok then return result end
    return {known = false, error = tostring(result), source = "via.gui.GUISystem.MessageLanguage"}
end

---Resolve game text in a requested UI language without changing the game's language.
---Omitting language preserves the native current-language read for catalogue validation.
function M.message(guid, language)
    if not guid then return nil end
    local ok, text = pcall(function()
        local td = assert(sdk.find_type_definition("via.gui.message"))
        if language then
            local enum_name = language == "zh" and "SimplelifiedChinese" or "English"
            local value = assert(M.enum("via.Language").values[enum_name], "缺少目标文字语言枚举")
            return M.method(td, "get", {"System.Guid", "via.Language"}, "System.String", true):call(nil, guid, value)
        end
        return M.method(td, "get", {"System.Guid"}, "System.String", true):call(nil, guid)
    end)
    if ok and type(text) == "string" then
        text = text:gsub("<[^>]->", ""):gsub("\r", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if text ~= "" and not text:find("Rejected", 1, true) then return text end
    end
    return nil
end

---Check an actual GUID through its own typed ToString method, not memory offsets.
---Unknown serialization stays unknown so placeholder detection cannot silently guess.
function M.guid_text(guid)
    if not guid then return nil end
    local ok, value = pcall(M.call, guid, "ToString", {}, "System.String")
    if ok and type(value) == "string" then return value:lower() end
    return nil
end

function M.job_name(id, language)
    local ok, text = pcall(function()
        local td = assert(sdk.find_type_definition("app.GUIBase"))
        local guid = M.method(td, "getJobNameMsgID", {"app.Character.JobEnum"},
            "System.Guid", true):call(nil, id)
        return M.message(guid, language)
    end)
    if ok and text then return text end
    return "Job" .. string.format("%02d", id)
end

---Capture the entire preallocated table, including None/ID 0 and disabled records.
---Presence alone does not mean learned; use both native record and context getters.
function M.records(actor)
    local list = assert(M.get(actor.context, "EnabledCustomSkills"), "学习记录集合为空")
    local records, map = {}, {}
    for i = 0, M.count(list) - 1 do
        local object = assert(M.item(list, i), "学习记录含空项")
        assert(M.type_of(object):get_full_name() == RECORD, "学习记录类型变化")
        assert(not M.type_of(object):is_value_type(), "当前版本仅支持引用类型学习记录")
        local id = M.integer(M.get(object, "CustomSkillID"))
        local record = {id = id, level = M.integer(M.get(object, "Level")),
            viewed = M.boolean(M.get(object, "IsViewedNew")), object = object, index = i,
            enabled = M.boolean(M.call(object, "get_IsEnableProp", {}, "System.Boolean"))}
        assert(id >= 0 and not map[id], "学习记录含重复或负技能 ID: " .. id)
        if id > 0 then
            record.effective = M.boolean(M.call(actor.context, "isCustomSkillEnable",
                {"app.HumanCustomSkillID"}, "System.Boolean", id))
            -- Check the native level independently as well: a matching stored Level
            -- alone must never conceal a stale/effective level after a transaction.
            record.native_level = M.integer(M.call(actor.context, "getCustomSkillLevel",
                {"app.HumanCustomSkillID"}, "app.HumanCustomSkillLevelNo", id))
            local seen = grade_states[record.level]
            if seen ~= nil and seen ~= record.enabled then grade_conflict = true end
            grade_states[record.level] = record.enabled
        end
        records[#records + 1], map[id] = record, record
    end
    return {list = list, records = records, map = map}
end

---Infer grade acquisition semantics only from actual native getter observations.
---A single unlearned grade must be observed before deletion; no zero-level guess.
function M.learning_model()
    local rows, disabled = {}, {}
    for level, learned in pairs(grade_states) do
        rows[#rows + 1] = {level = level, learned = learned}
        if not learned then disabled[#disabled + 1] = level end
    end
    table.sort(rows, function(a, b) return a.level < b.level end)
    local enabled = {}
    for _, row in ipairs(rows) do if row.learned then enabled[row.level] = true end end
    return {valid = not grade_conflict, observations = rows, enabled = enabled,
        unlearned_level = #disabled == 1 and disabled[1] or nil}
end

---Find one post-setter record without repeatedly sampling every native getter in bulk.
function M.find_record(actor, id)
    local list = M.get(actor.context, "EnabledCustomSkills")
    -- Current saves use a dense ID-indexed table. Validate the candidate before using
    -- it, and fall back to exact-ID search for future or differently ordered saves.
    if id >= 0 and id < M.count(list) then
        local candidate = M.item(list, id)
        if candidate and M.integer(M.get(candidate, "CustomSkillID")) == id then return candidate end
    end
    for index = 0, M.count(list) - 1 do
        local object = M.item(list, index)
        if M.integer(M.get(object, "CustomSkillID")) == id then return object end
    end
    return nil
end

---Scan the entire saved palette, including inactive vocations and Warfarer references.
function M.equipment(actor)
    local root = assert(M.get(actor.context, "EquipedSkills"), "职业技能槽尚不可用")
    local rows = {}
    for job = 0, M.count(root) - 1 do
        local palette = M.item(root, job)
        if palette then
            local slots = assert(M.get(palette, "Skills"), "职业技能槽含空集合")
            assert(M.type_of(slots):is_array(), "装备槽不是已核验的数组")
            for slot = 0, M.count(slots) - 1 do
                rows[#rows + 1] = {job = job, slot = slot, id = M.integer(M.item(slots, slot)),
                    array = slots}
            end
        end
    end
    assert(#rows > 0, "未能完整读取装备槽；为保护存档，停止修改")
    return rows
end

local function equipment_methods(actor)
    local td = M.type_of(actor.context)
    M.method(td, "setSkill", {"app.Character.JobEnum", "app.HumanCustomSkillID",
        "app.HumanSkillContext.SkillSlot"}, "System.Boolean", false)
    M.method(td, "getSkillID", {"app.Character.JobEnum", "app.HumanSkillContext.SkillSlot"},
        "app.HumanCustomSkillID", false)
    M.method(td, "getEquipList", {"app.Character.JobEnum"}, "app.HumanSkillContext.EquipedSkill", false)
end

---Cross-check saved palette indexing with native getters before allowing slot writes.
---The None/job-0 palette is a sentinel: keep it empty and never pass it to setSkill.
---@return integer none_id The reflected None skill value, not a guessed deletion value.
function M.equipment_contract(actor, rows)
    equipment_methods(actor)
    local jobs = M.enum("app.Character.JobEnum")
    local slots = M.enum("app.HumanSkillContext.SkillSlot")
    local none = assert(M.enum("app.HumanCustomSkillID").values.None, "未能核验空技能枚举")
    local palettes = {}
    for _, row in ipairs(rows) do
        assert(jobs.names[row.job] and slots.names[row.slot], "职业或技能槽枚举不匹配")
        if row.job == jobs.values.None then
            assert(row.id == none, "空职业哨兵槽含技能，停止修改")
        else
            if not palettes[row.job] then
                local palette = assert(M.call(actor.context, "getEquipList", {"app.Character.JobEnum"},
                    "app.HumanSkillContext.EquipedSkill", row.job), "原生职业技能槽不可用")
                assert(M.address(M.get(palette, "Skills")) == M.address(row.array), "职业技能槽索引不一致")
                palettes[row.job] = true
            end
            assert(M.native_slot(actor, row.job, row.slot) == row.id, "原生装备槽与保存记录不一致")
        end
    end
    return none
end

---Read the native slot, which is also checked after each unequip and recovery write.
function M.native_slot(actor, job, slot)
    return M.integer(M.call(actor.context, "getSkillID",
        {"app.Character.JobEnum", "app.HumanSkillContext.SkillSlot"}, "app.HumanCustomSkillID", job, slot))
end

---Use the game's setter so its own equipment notifications run; never write raw slots.
---A rejected setter is a transaction failure even if the saved array happened to change.
function M.native_set_skill(actor, job, slot, id)
    assert(job ~= M.enum("app.Character.JobEnum").values.None, "禁止修改空职业哨兵槽")
    local accepted = M.boolean(M.call(actor.context, "setSkill", {"app.Character.JobEnum",
        "app.HumanCustomSkillID", "app.HumanSkillContext.SkillSlot"}, "System.Boolean", job, id, slot))
    assert(accepted, "游戏未接受技能槽修改：" .. M.job_name(job) .. " / 槽位 " .. (slot + 1))
    assert(M.native_slot(actor, job, slot) == id, "原生装备槽回读不匹配")
end

---Read protected progress and core-skill data. The editor never writes these fields;
---if a native grant unexpectedly changes them, recovery verification must fail closed.
function M.guards(actor)
    local normal = assert(M.get(actor.context, "EnableNormalSkills"), "基础技能保护数据不可用")
    local out = {normal = {}, job = {}}
    local parts = {}
    for _, name in ipairs({"IsAllSkillEnable", "IsNormalSkillEnable"}) do
        out[name] = M.boolean(M.get(actor.context, name))
        parts[#parts + 1] = name .. ":" .. tostring(out[name])
    end
    for i = 0, M.count(normal) - 1 do
        local record = assert(M.item(normal, i), "基础技能记录含空项")
        local row = {id = M.integer(M.get(record, "NormalSkillID")),
            enabled = M.boolean(M.get(record, "IsEnable")), viewed = M.boolean(M.get(record, "IsViewedNew"))}
        out.normal[#out.normal + 1] = row
        parts[#parts + 1] = "N" .. row.id .. ":" .. tostring(row.enabled) .. ":" .. tostring(row.viewed)
    end
    local job = assert(M.call(actor.human, "get_JobContext", {}, "app.JobContext"), "职业保护数据不可用")
    for _, name in ipairs({"CurrentJob", "ConsumableExp", "ChangedJobBits", "QualifiedJobBits", "ViewedNewJobBits"}) do
        out.job[name] = M.integer(M.get(job, name))
        parts[#parts + 1] = name .. ":" .. out.job[name]
    end
    out.job.cumulative_exp = {}
    local exp = assert(M.get(job, "CulmativeExp"), "职业累计经验不可用")
    for i = 0, M.count(exp) - 1 do
        local value = M.integer(M.item(exp, i))
        out.job.cumulative_exp[#out.job.cumulative_exp + 1] = value
        parts[#parts + 1] = "J" .. i .. ":" .. value
    end
    out.fingerprint = table.concat(parts, "|")
    return out
end

function M.writer_contract(actor, snapshot)
    snapshot = snapshot or M.records(actor)
    -- Sampling checks cached signatures only. The full saved/native slot comparison
    -- belongs to transaction preparation, avoiding an extra palette scan every poll.
    equipment_methods(actor)
    assert(M.learning_model().valid, "同一等级的原生获取属性不一致，请导出诊断；停止修改")
    assert(not M.boolean(M.get(actor.context, "IsAllSkillEnable")), "全技能调试开关已开启，无法精确管理获取状态")
    for _, record in ipairs(snapshot.records) do
        if record.id > 0 then
            assert(record.enabled == record.effective, "原生获取状态与保存记录不一致: " .. record.id)
            assert(record.level == record.native_level, "原生技能等级与保存记录不一致: " .. record.id)
        end
    end
    local td = M.type_of(snapshot.list)
    assert(not td:is_array(), "学习记录不是可修改的 List<T>；请导出诊断")
    M.method(M.type_of(actor.context), "setCustomSkillEnable",
        {"app.HumanCustomSkillID", "app.HumanCustomSkillLevelNo"}, "System.Void", false)
    M.method(td, "RemoveAt", {"System.Int32"}, "System.Void", false)
    M.method(td, "Insert", {"System.Int32", RECORD}, "System.Void", false)
    return snapshot
end

function M.native_grant(actor, id, level)
    M.call(actor.context, "setCustomSkillEnable",
        {"app.HumanCustomSkillID", "app.HumanCustomSkillLevelNo"}, "System.Void", id, level)
end

---Protect original references across a native setter that might replace/remove rows.
---REFramework tracks add_ref for Lua GC; do not use permanent references or manual release.
function M.pin_records(snapshot)
    snapshot.list:add_ref()
    for _, record in ipairs(snapshot.records) do record.object:add_ref() end
end

function M.remove(list, index)
    assert(index >= 0 and index < M.count(list), "删除记录的下标越界")
    M.call(list, "RemoveAt", {"System.Int32"}, "System.Void", index)
end

---Restore the original list instance, order and fields; do not reconstruct game objects.
function M.restore(actor, before, equipment)
    if M.address(M.get(actor.context, "EnabledCustomSkills")) ~= M.address(before.list) then
        M.set(actor.context, "EnabledCustomSkills", before.list)
    end
    local structural = M.count(before.list) ~= #before.records
    if not structural then
        for i, record in ipairs(before.records) do
            if M.address(M.item(before.list, i - 1)) ~= M.address(record.object) then structural = true; break end
        end
    end
    -- Ordinary grade changes do not require clearing the preallocated table. Rebuild
    -- only after an unexpected structural mutation; retain original references/order.
    if structural then
        for i = M.count(before.list) - 1, 0, -1 do M.remove(before.list, i) end
    end
    for i, record in ipairs(before.records) do
        if M.integer(M.get(record.object, "CustomSkillID")) ~= record.id then M.set(record.object, "CustomSkillID", record.id) end
        if M.integer(M.get(record.object, "Level")) ~= record.level then M.set(record.object, "Level", record.level) end
        if M.boolean(M.get(record.object, "IsViewedNew")) ~= record.viewed then M.set(record.object, "IsViewedNew", record.viewed) end
        if structural then M.call(before.list, "Insert", {"System.Int32", RECORD}, "System.Void", i - 1, record.object) end
    end
    -- Restore learned records first, then use the native equipment setter to rebind
    -- slots. Raw-array repair could leave a different active equipment state behind.
    local current = M.equipment(actor)
    assert(#current == #equipment, "回滚时装备槽结构变化")
    for index, row in ipairs(equipment) do
        local now = current[index]
        assert(now.job == row.job and now.slot == row.slot, "回滚时职业槽索引变化")
        if row.job == M.enum("app.Character.JobEnum").values.None then
            assert(now.id == row.id, "空职业哨兵槽意外变化")
        elseif now.id ~= row.id or M.native_slot(actor, row.job, row.slot) ~= row.id then
            M.native_set_skill(actor, row.job, row.slot, row.id)
        end
    end
end

function M.describe_type(name)
    local td = sdk.find_type_definition(name)
    if not td then return {name = name, missing = true} end
    local fields, methods = {}, {}
    for _, field in ipairs(td:get_fields()) do
        fields[#fields + 1] = {name = field:get_name(), type = field:get_type():get_full_name(),
            static = field:is_static()}
    end
    for _, method in ipairs(td:get_methods()) do
        local params = {}
        for _, p in ipairs(method:get_param_types()) do params[#params + 1] = p:get_full_name() end
        methods[#methods + 1] = {name = method:get_name(), parameters = params,
            result = method:get_return_type():get_full_name(), static = method:is_static()}
    end
    local parent = td:get_parent_type()
    return {name = name, parent = parent and parent:get_full_name(),
        value_type = td:is_value_type(), fields = fields, methods = methods}
end

return M
