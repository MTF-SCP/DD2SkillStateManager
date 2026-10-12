-- SPDX-License-Identifier: MIT
-- Vocation transactions share the controller's preview/backup/dispatch lifecycle.
local access = require("DD2SkillStateManager/access")
local progress_access = require("DD2SkillStateManager/progress_access")
local operations = require("DD2SkillStateManager/operations")
local M = {}
local kinds = {vocation_unlock = true, vocation_unlock_all = true, vocation_lock = true, vocation_rank = true, jp = true}

function M.accepts(kind) return kinds[kind] == true end

---Produce portable requests; changing a vocation's rank never grants its skills.
function M.specification(catalog, kind, target, job_id, value)
    assert(M.accepts(kind), "未知职业操作")
    assert(target == "arisen" or target == "pawn" or target == "both", "未知角色范围")
    local roles = target == "both" and {"arisen", "pawn"} or {target}
    if kind ~= "jp" and kind ~= "vocation_unlock_all" then
        local policy = assert(progress_access.policy(assert(catalog.jobs[job_id], "职业不在目录中")), "未知职业适用规则")
        if policy == "arisen" then
            assert(target ~= "pawn", "主随从不能使用此职业")
            roles = {"arisen"}
        end
    end
    if kind == "jp" then assert(math.tointeger(value) and value >= 0 and value <= 2147483647, "JP 需要为有效 Int32 整数") end
    if kind == "vocation_rank" then assert(math.tointeger(value) and value >= 1, "职业等级必须为正整数") end
    local items, skipped = {}, {}
    for _, role in ipairs(roles) do
        if kind == "vocation_unlock_all" then
            for _, id in ipairs(catalog.job_order) do
                local job = catalog.jobs[id]
                local policy = progress_access.policy(job)
                if not policy or (role == "pawn" and policy == "arisen") then
                    skipped[#skipped + 1] = {name = job.name, role = role,
                        reason_key = policy and "pawn_job" or "unknown_job", reason_data = {role = role}}
                else items[#items + 1] = {role = role, job_id = id} end
            end
        else items[#items + 1] = {role = role, job_id = job_id} end
    end
    return {domain = "progress", kind = kind, target = target, roles = roles, job_id = job_id, value = value,
        stamp = catalog.stamp, items = items, changes = {}, skipped = skipped, title = kind}
end

local function guard(actor, snapshot)
    local state = operations.state_export(actor, snapshot)
    -- Job data has its own operation-specific whitelist, not the skill editor's immutable guard.
    state.protected_progress.job = nil
    -- access.guards' cached fingerprint includes job fields too. Comparing it
    -- here would reject every intended JP/rank/qualification change; compare
    -- the remaining raw guard values while verify() checks job data separately.
    state.protected_progress.fingerprint = nil
    return {skills = state, character = progress_access.protected(actor)}
end

local function canonical(value) return assert(json.dump_string(value), "状态指纹编码失败") end

---Name the first changed protected field without exporting game references.
local function difference(before, after, path)
    if type(before) ~= type(after) then return path end
    if type(before) ~= "table" then return before ~= after and path or nil end
    for key, value in pairs(before) do
        local changed = difference(value, after[key], path .. "." .. tostring(key))
        if changed then return changed end
    end
    for key in pairs(after) do if before[key] == nil then return path .. "." .. tostring(key) end end
end

---UI sampling stays portable and independent of the ordinary skill writer contract.
function M.sample(actor, catalog, recovery_contract)
    local data = progress_access.read(actor, catalog)
    local protected_ok, why = pcall(function()
        assert(data.capabilities.recovery.ok, "精确经验恢复接口不可用")
        if recovery_contract == nil then access.writer_contract(actor)
        else assert(recovery_contract, "技能恢复契约不可用") end
        progress_access.protected(actor)
    end)
    return {ok = true, data = progress_access.export(data), protected_ok = protected_ok,
        protection_error = not protected_ok and tostring(why) or nil}
end

---Validate one proposed field change; the caller validates all actors before writing.
local function prepare_change(data, spec, item)
    local selected = item.job_id
    local row = selected and data.jobs[selected]
    local before, after
    if spec.kind == "jp" then
        assert(data.capabilities.jp.ok, "JP 接口不可用，请导出诊断")
        before, after = data.fields.ConsumableExp, spec.value
    elseif spec.kind == "vocation_rank" then
        assert(data.capabilities.rank.ok and row.rank_ok, "职业等级接口不可用，请导出诊断")
        assert(spec.value <= row.maximum, "目标超过游戏最高职业等级")
        before, after = row.rank, spec.value
    else
        assert(data.capabilities.qualification.ok and row.qualified ~= nil, "职业资格接口不可用，请导出诊断")
        before, after = row.qualified, spec.kind ~= "vocation_lock"
        if spec.kind == "vocation_lock" then
            assert(not row.basic, "基础职业不可锁定")
            assert(data.fields.CurrentJob ~= spec.job_id, "职业正在使用，请先转职")
        end
    end
    return {role = item.role, field = spec.kind == "jp" and "jp_balance"
        or (spec.kind == "vocation_rank" and "vocation_rank_label" or "qualification"),
        job_id = selected, before = before, after = after, writes = before ~= after}
end

---Validate every target and every recovery primitive before the first live write.
function M.prepare(catalog, spec)
    assert(access.in_game(), "请在存档正常游戏阶段操作")
    assert(spec.domain == "progress" and catalog.stamp == spec.stamp, "职业目录已变化，请重新预览")
    local fresh = M.specification(catalog, spec.kind, spec.target, spec.job_id, spec.value)
    assert(table.concat(fresh.roles, ",") == table.concat(spec.roles, ","), "职业角色范围已变化")
    local states, sources, preview, parts = {}, {}, {}, {catalog.stamp, access.address(access.scene())}
    local actual_writes = 0
    for _, role in ipairs(spec.roles) do
        local actor = access.actor(role)
        local data = progress_access.read(actor, catalog)
        assert(data.capabilities.recovery.ok, "精确经验恢复接口不可用，请导出诊断")
        assert(data.fields.CurrentJob > 0 and catalog.jobs[data.fields.CurrentJob], "角色职业尚未载入，请导出诊断")
        local snapshot = access.writer_contract(actor)
        local state = {actor = actor, data = data, records = snapshot, equipment = access.equipment(actor), changes = {}}
        state.guard = guard(actor, snapshot)
        state.guard_fingerprint = canonical(state.guard)
        state.equipment_none = access.equipment_contract(actor, state.equipment)
        parts[#parts + 1] = actor.identity .. "|" .. access.address(data.context) .. "|" .. access.address(data.array)
            .. "|" .. canonical(progress_access.export(data)) .. "|" .. state.guard_fingerprint
        for _, item in ipairs(fresh.items) do
            if item.role == role then
                local change = prepare_change(data, spec, item)
                state.changes[#state.changes + 1] = change
                preview[#preview + 1] = change
                if change.writes then actual_writes = actual_writes + 1; state.writes = true end
            end
        end
        states[#states + 1] = state
        sources[#sources + 1] = {role = role, data = data}
    end
    if #states == 2 then
        assert(access.address(states[1].data.context) ~= access.address(states[2].data.context)
            and access.address(states[1].actor.context) ~= access.address(states[2].actor.context), "双方意外共用上下文")
    end
    -- An accessible Arisen can disambiguate bits even during a Pawn-only operation.
    -- Its observation is fingerprinted, but absence does not block Pawn rank/JP operations.
    if spec.kind == "vocation_lock" and spec.roles[1] == "pawn" then
        local ok, other = pcall(function() return progress_access.read(access.actor("arisen"), catalog) end)
        if ok then
            sources[#sources + 1] = {role = "arisen", data = other}
            parts[#parts + 1] = "mapping-source|" .. canonical(progress_access.export(other))
        end
    end
    local mapping = progress_access.mapping(catalog, sources)
    if spec.kind == "vocation_lock" then assert(mapping.known, "职业资格位图无法唯一核验，请导出诊断") end
    parts[#parts + 1] = canonical(mapping)
    fresh.changes = preview
    return {spec = fresh, states = states, mapping = mapping, preview = preview, unequips = {},
        actual_writes = actual_writes, actual_slot_writes = 0, fingerprint = table.concat(parts, "||")}
end

local function verify(state, catalog, spec, mapping, rollback)
    local now = progress_access.read(state.actor, catalog)
    local old, selected = state.data, spec.job_id
    assert(access.address(now.context) == access.address(old.context) and access.address(now.array) == access.address(old.array), "职业引用意外变化")
    assert(#now.experience == #old.experience, "职业经验长度意外变化")
    local active = not rollback and state.writes
    local qualification_kind = spec.kind == "vocation_unlock" or spec.kind == "vocation_unlock_all" or spec.kind == "vocation_lock"
    local qualified, qualification_count, qualification_mask = {}, 0, 0
    if active and qualification_kind then
        for _, change in ipairs(state.changes) do
            if change.writes then
                qualified[change.job_id] = change.after
                qualification_count = qualification_count + 1
                if mapping.known then qualification_mask = qualification_mask | (1 << (change.job_id - mapping.shift)) end
            end
        end
    end
    for name, value in pairs(old.fields) do
        if active and spec.kind == "jp" and name == "ConsumableExp" then
            assert(now.capabilities.jp.ok and now.fields[name] == spec.value, "JP 回读不匹配")
        elseif active and qualification_kind and name == "QualifiedJobBits" then
            local delta = now.fields[name] ~ value
            if spec.kind == "vocation_lock" then
                assert(now.fields[name] == value & (~(1 << (selected - mapping.shift)) & 0xFFFFFFFF), "职业锁定位图回读不匹配")
            else
                local added, remaining = 0, delta
                while remaining ~= 0 do remaining = remaining & (remaining - 1); added = added + 1 end
                assert(added == qualification_count and now.fields[name] & value == value, "解锁资格位数量不匹配或清除了其他资格")
                if mapping.known then assert(delta == qualification_mask, "解锁资格位与原生映射不一致") end
            end
        else assert(now.fields[name] == value, "其他职业字段变化: " .. name) end
    end
    for index, value in ipairs(old.experience) do
        if active and spec.kind == "vocation_rank" and index == old.jobs[selected].index + 1 then
            local row = now.jobs[selected]
            assert(row.rank_ok and row.rank == spec.value and now.experience[index] == row.exp, "职业等级或经验回读不匹配")
        else assert(now.experience[index] == value, "其他职业经验意外变化") end
    end
    for _, id in ipairs(old.order) do
        local a, b = old.jobs[id], now.jobs[id]
        local qualification = qualified[id] ~= nil
        -- Explicit branches retain false booleans; no 'and/or' default may turn false into nil.
        if qualification then assert(b.qualified == qualified[id], "目标职业资格不匹配")
        else assert(b.qualified == a.qualified, "其他职业资格变化") end
        if a.rank_ok then
            assert(b.rank_ok and b.maximum == a.maximum, "最高职业等级变化")
            if not (active and spec.kind == "vocation_rank" and id == selected) then
                assert(b.rank == a.rank and b.exp == a.exp, "其他原生职业等级或经验变化")
            end
        end
    end
    local current_guard = guard(state.actor)
    local changed = difference(state.guard, current_guard, "protected")
    assert(not changed, "人物等级、被动能力或技能装备出现意外变化: " .. tostring(changed))
end

---Keep logs portable and include the complete original experience, not just rank.
function M.backup(prepared)
    local out = {domain = "progress", kind = prepared.spec.kind, target = prepared.spec.target,
        job_id = prepared.spec.job_id, value = prepared.spec.value, mapping = prepared.mapping, actors = {}}
    for _, state in ipairs(prepared.states) do
        out.actors[#out.actors + 1] = {role = state.actor.role, identity = state.actor.identity,
            progress = progress_access.export(state.data), protected = state.guard}
    end
    return out
end

---Atomic role updates; any failed write restores exact progress and skill snapshots.
---Guard-only character/augment mutations are never silently repaired or reported as success.
function M.execute(prepared, catalog)
    for _, state in ipairs(prepared.states) do
        progress_access.pin(state.data); access.pin_records(state.records)
    end
    local ok, why = xpcall(function()
        for _, state in ipairs(prepared.states) do
            for _, change in ipairs(state.changes) do
                if change.writes then
                    local kind = prepared.spec.kind == "vocation_unlock_all" and "vocation_unlock" or prepared.spec.kind
                    progress_access.apply(state.data, kind, change.job_id, prepared.spec.value, prepared.mapping)
                end
            end
        end
        for _, state in ipairs(prepared.states) do verify(state, catalog, prepared.spec, prepared.mapping, false) end
    end, debug.traceback)
    if ok then return true, "已修改 " .. prepared.actual_writes .. " 项职业/JP 状态", false end
    local failures = {}
    for index = #prepared.states, 1, -1 do
        local state = prepared.states[index]
        local restored, failure = xpcall(function()
            progress_access.restore(state.actor, state.data)
            access.restore(state.actor, state.records, state.equipment)
        end, debug.traceback)
        if not restored then failures[#failures + 1] = state.actor.role .. ": " .. tostring(failure) end
    end
    for _, state in ipairs(prepared.states) do
        local restored, failure = xpcall(function() verify(state, catalog, prepared.spec, prepared.mapping, true) end, debug.traceback)
        if not restored then failures[#failures + 1] = state.actor.role .. ": " .. tostring(failure) end
    end
    if #failures > 0 then return false, tostring(why) .. "\n恢复失败：" .. table.concat(failures, "\n"), true end
    return false, "已恢复原始职业经验及其他修改：" .. tostring(why), false
end

return M
