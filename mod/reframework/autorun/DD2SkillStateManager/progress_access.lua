-- SPDX-License-Identifier: MIT
-- Vocation adapter: reflected data, native setters and exact recovery primitives.
-- This module registers no callbacks. Mutation order belongs to progress.lua.
local access = require("DD2SkillStateManager/access")
local M = {}
local JOB = "app.Character.JobEnum"
local job_fields = {"CurrentJob", "ConsumableExp", "ChangedJobBits", "QualifiedJobBits", "ViewedNewJobBits"}
local scalar_cache = {} -- Type metadata only; never retain growth/gear instances between callbacks.

local function contract(object, name, params, result)
    return access.method(access.type_of(object), name, params, result, false)
end

---Known DD2 vocation policy matches the skill editor. Future unknown jobs are read only.
function M.policy(job)
    if job.number >= 1 and job.number <= 6 then return "both" end
    if job.number >= 7 and job.number <= 10 then return "arisen" end
    return nil
end

local function feature(object, methods)
    local ok, why = pcall(function()
        for _, row in ipairs(methods) do contract(object, row[1], row[2], row[3]) end
    end)
    return {ok = ok, error = not ok and tostring(why) or nil}
end

---Read raw progress even if one native feature has changed signature.
---Returned references are local to one update callback; export() removes all of them.
function M.read(actor, catalog)
    local context = access.call(actor.human, "get_JobContext", {}, "app.JobContext")
    assert(context, "职业上下文不可用")
    local out = {context = context, fields = {}, jobs = {}, order = catalog.job_order, capabilities = {}}
    for _, name in ipairs(job_fields) do
        access.field_contract(context, name, name == "CurrentJob" and JOB
            or (name == "ConsumableExp" and "System.Int32" or "System.UInt32"))
        out.fields[name] = access.integer(access.get(context, name))
    end
    access.field_contract(context, "CulmativeExp", "System.Int32[]")
    assert(out.fields.ConsumableExp >= 0 and out.fields.ConsumableExp <= 2147483647, "JP 超出 Int32 范围")
    assert(out.fields.QualifiedJobBits >= 0 and out.fields.QualifiedJobBits <= 0xFFFFFFFF, "职业资格位图越界")
    out.array = assert(access.get(context, "CulmativeExp"), "职业经验数组不可用")
    assert(access.type_of(out.array):get_full_name() == "System.Int32[]", "职业经验数组类型变化")
    out.experience, out.boxes = {}, {}
    for index = 0, access.count(out.array) - 1 do
        local boxed = access.item(out.array, index)
        assert(access.type_of(boxed):get_full_name() == "System.Int32", "职业经验元素类型变化")
        out.experience[index + 1], out.boxes[index + 1] = access.integer(boxed), boxed
    end
    local recovery_ok, setter = pcall(access.int_array_contract, out.array)
    out.capabilities.recovery = {ok = recovery_ok, setter = recovery_ok and setter or nil,
        error = not recovery_ok and tostring(setter) or nil}
    out.capabilities.jp = feature(context, {{"get_ConsumableExpProp", {}, "System.Int32"},
        {"set_ConsumableExpProp", {"System.Int32"}, "System.Void"}})
    if out.capabilities.jp.ok then
        local ok, why = pcall(function()
            assert(access.integer(access.call(context, "get_ConsumableExpProp", {}, "System.Int32")) == out.fields.ConsumableExp,
                "JP 原生 getter 与字段不一致")
        end)
        out.capabilities.jp = {ok = ok, error = not ok and tostring(why) or nil}
    end
    out.capabilities.rank = feature(context, {{"calcJobRank", {JOB}, "System.UInt32"},
        {"getJobExp", {JOB}, "System.Int32"}, {"get_JobIndex", {}, "System.Int32"},
        {"getMaxJobRank", {JOB}, "System.Int32"}, {"setJobExpWithJobRank", {JOB, "System.UInt32"}, "System.Void"}})
    -- Cross-check indexing, instead of writing a guessed job-ID offset into an array.
    if out.capabilities.rank.ok then
        local ok, why = pcall(function()
            assert(access.count(out.array) == #catalog.job_order, "职业与经验数组数量不一致")
            local index = access.integer(access.call(context, "get_JobIndex", {}, "System.Int32"))
            assert(index == out.fields.CurrentJob - 1, "当前职业经验下标不匹配")
        end)
        if not ok then out.capabilities.rank = {ok = false, error = tostring(why)} end
    end
    out.capabilities.qualification = feature(context, {{"isJobQualified", {JOB}, "System.Boolean"},
        {"setJobQualified", {JOB}, "System.Void"}})
    for _, id in ipairs(catalog.job_order) do
        local info = catalog.jobs[id]
        local row = {id = id, supported = M.policy(info), basic = info.number >= 1 and info.number <= 4}
        if out.capabilities.qualification.ok then
            local ok, value = pcall(function()
                return access.boolean(access.call(context, "isJobQualified", {JOB}, "System.Boolean", id))
            end)
            if ok then row.qualified = value else row.qualification_error = tostring(value) end
        end
        if out.capabilities.rank.ok then
            local ok, why = pcall(function()
                row.rank = access.integer(access.call(context, "calcJobRank", {JOB}, "System.UInt32", id))
                row.maximum = access.integer(access.call(context, "getMaxJobRank", {JOB}, "System.Int32", id))
                row.exp = access.integer(access.call(context, "getJobExp", {JOB}, "System.Int32", id))
                row.index = id - 1
                assert(row.maximum >= 1 and row.maximum <= 128, "最高职业等级异常，请导出诊断")
                assert(row.rank >= 1 and row.rank <= row.maximum, "职业等级异常，请导出诊断")
                assert(row.exp >= 0 and out.experience[row.index + 1] == row.exp, "职业经验保存值与原生值不一致")
            end)
            row.rank_ok, row.rank_error = ok, not ok and tostring(why) or nil
        end
        out.jobs[id] = row
    end
    return out
end

---Resolve one-based versus zero-based qualification bits using live native queries.
---Basic jobs are intrinsically available; Pawn-exclusive jobs provide no Pawn evidence.
---Ambiguous observations disable locking; native unlocking needs no inferred mask.
function M.mapping(catalog, sources)
    local candidates = {}
    for _, shift in ipairs({0, 1}) do
        local fits, observed = true, 0
        for _, source in ipairs(sources) do
            for _, id in ipairs(catalog.job_order) do
                local row = source.data.jobs[id]
                if not row.basic and row.supported and (source.role == "arisen" or row.supported == "both") then
                    local bit_index = id - shift
                    if row.qualified == nil or bit_index < 0 or bit_index >= 32 then fits = false
                    else
                        observed = observed + 1
                        if ((source.data.fields.QualifiedJobBits >> bit_index) & 1 == 1) ~= row.qualified then fits = false end
                    end
                end
            end
        end
        if fits and observed > 0 then candidates[#candidates + 1] = shift end
    end
    return {known = #candidates == 1, shift = #candidates == 1 and candidates[1] or nil, candidates = candidates}
end

local function scalar_fields(object)
    local td = access.type_of(object)
    local type_name = td:get_full_name()
    local descriptors = scalar_cache[type_name]
    if not descriptors then
        descriptors = {}
        for _, field in ipairs(td:get_fields()) do
            if not field:is_static() then
                descriptors[#descriptors + 1] = {name = field:get_name(), kind = field:get_type():get_full_name(), enum = field:get_type():is_enum()}
            end
        end
        scalar_cache[type_name] = descriptors
    end
    local out = {}
    for _, descriptor in ipairs(descriptors) do
            local name, kind = descriptor.name, descriptor.kind
            local value = access.get(object, name)
            if kind == "System.Boolean" then out[name] = access.boolean(value)
            elseif kind == "System.Int32" or kind == "System.UInt32" or descriptor.enum then out[name] = access.integer(value)
            elseif kind == "System.Single" then
                assert(type(value) == "number" and value == value and math.abs(value) < math.huge, "保护数据浮点值异常")
                out[name] = value
            else error("保护数据出现未知字段类型: " .. kind .. " / " .. name) end
    end
    assert(next(out), "保护数据没有可读字段")
    return out
end

---Capture character level/growth and all learned/equipped augments as immutable guards.
---Unknown layouts fail closed for progress editing, without disabling skill editing.
function M.protected(actor)
    local status = access.call(actor.human, "get_StatusContext", {}, "app.HumanStatusContext")
    local growth = assert(access.get(status, "_IncreaseParams"), "成长属性不可用")
    local ability = access.call(actor.human, "get_AbilityContext", {}, "app.AbilityContext")
    assert(status and ability, "人物等级或被动能力上下文不可用")
    local weight = access.get(status, "_ItemIncreaseWeight")
    assert(type(weight) == "number" and weight == weight and math.abs(weight) < math.huge, "人物成长保护字段不可读")
    local out = {status_identity = access.address(status), level = access.integer(access.get(status, "_Level")),
        exp = access.integer(access.get(status, "_Exp")), growth_identity = access.address(growth),
        growth = scalar_fields(growth), item_weight = weight,
        extra_boost = access.integer(access.get(status, "_AcquiredExtraStatusBoost")),
        ability_identity = access.address(ability), abilities = {}, equipment = {},
        extra_slot = access.boolean(access.get(ability, "IsAdditionalSlotUnlocked"))}
    local learned = assert(access.get(ability, "EnableAbilities"), "被动能力记录不可用")
    local palettes = assert(access.get(ability, "EquipedAbilities"), "被动能力装备不可用")
    out.learned_identity, out.palettes_identity = access.address(learned), access.address(palettes)
    local job = access.call(actor.human, "get_JobContext", {}, "app.JobContext")
    local gear = assert(access.get(job, "EquipedArmors"), "职业武器和护甲配置不可用")
    out.gear_identity, out.gear = access.address(gear), {}
    for index = 0, access.count(gear) - 1 do
        local item = access.item(gear, index)
        out.gear[#out.gear + 1] = {index = index, present = item ~= nil,
            values = item and scalar_fields(item) or {}}
    end
    for index = 0, access.count(learned) - 1 do
        local row = assert(access.item(learned, index), "被动能力含空记录")
        out.abilities[#out.abilities + 1] = {id = access.integer(access.get(row, "AbilityID")),
            enabled = access.boolean(access.get(row, "IsEnable")), viewed = access.boolean(access.get(row, "IsViewedNew"))}
    end
    for index = 0, access.count(palettes) - 1 do
        local row = access.item(palettes, index)
        local palette = {index = index, present = row ~= nil, values = {}}
        if row then
            local array = assert(access.get(row, "Abilities"), "被动能力槽为空")
            for slot = 0, access.count(array) - 1 do palette.values[#palette.values + 1] = access.integer(access.item(array, slot)) end
        end
        out.equipment[#out.equipment + 1] = palette
    end
    return out
end

---Portable, deterministic progress data for UI, logs and preview fingerprints.
function M.export(data)
    local out = {fields = data.fields, experience = data.experience, jobs = {}, capabilities = data.capabilities}
    for _, id in ipairs(data.order) do out.jobs[#out.jobs + 1] = data.jobs[id] end
    return out
end

---Pin boxed copies for exact experience recovery inside the final transaction only.
function M.pin(data)
    data.context:add_ref(); data.array:add_ref()
    for _, boxed in ipairs(data.boxes) do boxed:add_ref() end
end

---Invoke only the requested native setter, or the validated single qualification bit.
function M.apply(data, kind, job_id, value, mapping)
    if kind == "vocation_rank" then
        access.call(data.context, "setJobExpWithJobRank", {JOB, "System.UInt32"}, "System.Void", job_id, value)
    elseif kind == "jp" then
        access.call(data.context, "set_ConsumableExpProp", {"System.Int32"}, "System.Void", value)
    elseif kind == "vocation_unlock" then
        access.call(data.context, "setJobQualified", {JOB}, "System.Void", job_id)
    elseif kind == "vocation_lock" then
        assert(mapping.known and not data.jobs[job_id].basic, "资格位图无法核验或基础职业不可锁定")
        local mask = 1 << (job_id - mapping.shift)
        access.set(data.context, "QualifiedJobBits", data.fields.QualifiedJobBits & (~mask & 0xFFFFFFFF))
    else error("未知职业操作") end
end

---Restore exact original scalars and boxed experience values, not merely vocation rank.
---Unexpected context replacement is unsafe to repair and produces the global writer lock.
function M.restore(actor, data)
    local context = access.call(actor.human, "get_JobContext", {}, "app.JobContext")
    assert(access.address(context) == access.address(data.context), "恢复时职业上下文引用变化")
    if access.address(access.get(context, "CulmativeExp")) ~= access.address(data.array) then
        access.set(context, "CulmativeExp", data.array)
    end
    assert(access.count(data.array) == #data.experience, "恢复时职业经验长度变化")
    for index, value in ipairs(data.experience) do
        if access.integer(access.item(data.array, index - 1)) ~= value then
            assert(access.integer(data.boxes[index]) == value, "原始经验装箱值意外变化")
            access.restore_int_element(data.array, index - 1, data.boxes[index])
        end
    end
    for _, name in ipairs(job_fields) do
        if access.integer(access.get(context, name)) ~= data.fields[name] then access.set(context, name, data.fields[name]) end
    end
end

return M
