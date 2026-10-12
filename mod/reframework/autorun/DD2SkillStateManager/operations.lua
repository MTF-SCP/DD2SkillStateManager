-- SPDX-License-Identifier: MIT
local access = require("DD2SkillStateManager/access")
local catalog_api = require("DD2SkillStateManager/catalog")
local M = {}
local labels = {arisen = "觉醒者", pawn = "主随从"}

---Build an immutable-in-practice operation specification from the selected native catalogue.
---Acquisition is explicit and verified by native getters, separate from raw grades.
function M.specification(catalog, kind, skill_id, level, job_id)
    local spec = {kind = kind, stamp = catalog.stamp, changes = {}, skipped = {}}
    if kind == "set" or kind == "delete" then
        local skill = assert(catalog.by_id[skill_id], "技能已不在当前目录中")
        assert(skill.valid, skill.reason)
        if kind == "set" then
            local permitted, why = catalog_api.grantable(catalog, skill, level)
            assert(permitted, why)
        end
        spec.changes[1] = {id = skill_id, level = level, learned = kind ~= "delete", target = skill.target}
        spec.title = (kind == "delete" and "删除技能：" or "设置技能：") .. skill.name
    else
        assert(kind == "job_all" or kind == "all", "未知操作")
        local ids = kind == "all" and catalog.order or assert(catalog.jobs[job_id], "职业不存在").skills
        for _, id in ipairs(ids) do
            local skill = catalog.by_id[id]
            local highest = catalog_api.highest(catalog, skill)
            if highest ~= nil then
                spec.changes[#spec.changes + 1] = {id = id, level = highest, learned = true, target = skill.target}
            else
                spec.skipped[#spec.skipped + 1] = {id = id, name = skill.name,
                    reason_key = "unavailable",
                    reason = skill.reason ~= "" and skill.reason or "内容未拥有或所有权未知"}
            end
        end
        spec.title = kind == "all" and "学习全部职业技能" or ("学习职业全部技能：" .. catalog.jobs[job_id].name)
    end
    assert(#spec.changes > 0, "范围内没有可以修改的技能")
    return spec
end

local function portable_records(snapshot, learned_only)
    local result = {}
    for _, record in ipairs(snapshot.records) do
        if not learned_only or (record.id > 0 and record.enabled) then
            result[#result + 1] = {id = record.id, level = record.level, viewed = record.viewed,
                enabled = record.enabled, effective = record.effective, native_level = record.native_level}
        end
    end
    return result
end

local function portable_equipment(rows)
    local result = {}
    for _, row in ipairs(rows) do result[#result + 1] = {job = row.job, slot = row.slot, id = row.id} end
    return result
end

local function fingerprint(state)
    local pieces = {state.actor.identity, access.address(state.before.list), state.guards.fingerprint}
    for _, record in ipairs(state.before.records) do
        pieces[#pieces + 1] = record.id .. ":" .. record.level .. ":" .. tostring(record.viewed)
            .. ":" .. tostring(record.enabled) .. ":" .. tostring(record.effective)
    end
    for _, row in ipairs(state.equipment) do
        pieces[#pieces + 1] = "E" .. row.job .. ":" .. row.slot .. ":" .. row.id
    end
    return table.concat(pieces, "|")
end

---Validate both actors before any mutation and retain exact ordered before-state snapshots.
function M.prepare(catalog, spec)
    assert(access.in_game(), "请在存档正常游戏阶段操作")
    assert(catalog.stamp == spec.stamp, "技能目录已变化，请重新预览")
    local need_pawn = false
    for _, change in ipairs(spec.changes) do if change.target == "both" then need_pawn = true end end
    local states = {}
    for _, role in ipairs(need_pawn and {"arisen", "pawn"} or {"arisen"}) do
        local actor = access.actor(role)
        states[#states + 1] = {actor = actor, before = access.writer_contract(actor),
            equipment = access.equipment(actor), guards = access.guards(actor),
            expected = {}, touched = {}, actions = {}, unequips = {}}
    end
    if #states == 2 then
        assert(access.address(states[1].actor.context) ~= access.address(states[2].actor.context),
            "双方意外引用了同一技能上下文，停止操作")
    end
    local preview, unequips, fingerprint_parts = {}, {}, {spec.stamp, access.address(access.scene())}
    local accepted = {kind = spec.kind, title = spec.title, stamp = spec.stamp, changes = {}, skipped = {}}
    for _, item in ipairs(spec.skipped) do accepted.skipped[#accepted.skipped + 1] = item end
    local bulk = spec.kind == "job_all" or spec.kind == "all"
    local actual_writes, actual_slot_writes = 0, 0
    for _, state in ipairs(states) do
        state.none_id = access.equipment_contract(state.actor, state.equipment)
        state.expected_equipment = portable_equipment(state.equipment)
        for _, record in ipairs(state.before.records) do
            state.expected[record.id] = {level = record.level, viewed = record.viewed,
                enabled = record.enabled, effective = record.effective}
        end
        fingerprint_parts[#fingerprint_parts + 1] = fingerprint(state)
    end
    for _, change in ipairs(spec.changes) do
        local skill = assert(catalog.by_id[change.id], "技能已从目录移除")
        assert(skill.valid and skill.target == change.target, "技能归属已变化")
        if change.learned then
            local permitted, why = catalog_api.grantable(catalog, skill, change.level)
            assert(permitted, why)
        end
        local blocked, reason_key, reason_data
        -- A blocker on either actor skips the whole skill, never just one side of sync.
        for _, state in ipairs(states) do
            if state.actor.role == "arisen" or change.target == "both" then
                local before = state.before.map[change.id]
                if before and before.enabled and not skill.variants[before.level] then
                    blocked = labels[state.actor.role] .. "现有等级不在参数表中，请导出诊断"
                    reason_key, reason_data = "unknown_level", {role = state.actor.role, level = before.level}
                end
                -- Learning in bulk is monotonic. An older save/another mod may have
                -- set a dummy or currently unverified higher grade; skip both actors
                -- together instead of silently downgrading while "learning all".
                if bulk and before and before.enabled and change.level < before.level then
                    blocked = labels[state.actor.role] .. "已有原始 Lv" .. before.level
                        .. "，高于当前可用最高 Lv" .. change.level .. "；批量学习保留现状，可单项设置。"
                    reason_key, reason_data = "keep_higher", {role = state.actor.role, level = before.level, maximum = change.level}
                end
                local writes = change.learned and (not before or not before.enabled or before.level ~= change.level)
                    or (not change.learned and before ~= nil and before.enabled)
                if writes and not change.learned and access.learning_model().unlearned_level == nil then
                    blocked = "未能从原生属性核实唯一的未获取等级，请导出诊断；不删除预置记录"
                    reason_key, reason_data = "unlearned", nil
                end
            end
        end
        if blocked then
            if not bulk then error(blocked) end
            accepted.skipped[#accepted.skipped + 1] = {id = change.id, name = skill.name, reason = blocked,
                reason_key = reason_key, reason_data = reason_data}
        else
            accepted.changes[#accepted.changes + 1] = change
            for _, state in ipairs(states) do
                if state.actor.role == "arisen" or change.target == "both" then
                    local before = state.before.map[change.id]
                    local writes = change.learned and (not before or not before.enabled or before.level ~= change.level)
                        or (not change.learned and before ~= nil and before.enabled)
                    if writes then
                        state.touched[change.id] = true
                        local desired_level = change.learned and change.level or access.learning_model().unlearned_level
                        state.actions[#state.actions + 1] = {id = change.id, learned = change.learned,
                            level = desired_level, target = change.target}
                        local viewed
                        if before then viewed = before.viewed end -- Preserve false as well as true.
                        state.expected[change.id] = {level = desired_level, viewed = viewed,
                            enabled = change.learned, effective = change.learned}
                        actual_writes = actual_writes + 1
                    end
                    -- A true no-op retains equipment. Explicit deletion also repairs
                    -- stale slots referencing an already disabled skill. Scan every
                    -- saved vocation, including inactive and Warfarer palettes.
                    if writes or not change.learned then
                        for index, row in ipairs(state.equipment) do
                            if row.id == change.id then
                                state.unequips[#state.unequips + 1] = row
                                state.expected_equipment[index].id = state.none_id
                                unequips[#unequips + 1] = {role = state.actor.role, job = row.job,
                                    job_name = catalog.jobs[row.job] and catalog.jobs[row.job].name or ("Job" .. row.job), slot = row.slot + 1,
                                    id = row.id, name = skill.name}
                                actual_slot_writes = actual_slot_writes + 1
                            end
                        end
                    end
                    preview[#preview + 1] = {role = state.actor.role, id = change.id, name = skill.name,
                        before_learned = before and before.enabled or false, before_level = before and before.level,
                        after_learned = change.learned, after_level = change.level,
                        writes = writes}
                end
            end
        end
    end
    return {spec = accepted, states = states, preview = preview, unequips = unequips,
        actual_writes = actual_writes, actual_slot_writes = actual_slot_writes,
        fingerprint = table.concat(fingerprint_parts, "||")}
end

local function verify_equipment(expected, current)
    assert(#expected == #current, "装备槽数量发生意外变化")
    for i, old in ipairs(expected) do
        local new = current[i]
        assert(old.job == new.job and old.slot == new.slot and old.id == new.id,
            "装备槽发生意外变化，正在回滚")
    end
end

---Check the full transaction boundary, not only the selected learning records.
---equipment_only compares original learning data with planned empty slots before grants.
local function verify_state(state, rollback, equipment_only)
    local current = access.records(state.actor)
    assert(access.address(current.list) == access.address(state.before.list), "学习记录集合引用意外变化")
    local expected = (rollback or equipment_only) and state.before.map or state.expected
    local count = 0
    for id, record in pairs(expected) do
        count = count + 1
        local actual = current.map[id]
        assert(actual and actual.level == record.level, "技能回读不匹配: " .. id)
        if id > 0 then assert(actual.native_level == record.level, "原生技能等级回读不匹配: " .. id) end
        assert(actual.enabled == record.enabled and actual.effective == record.effective,
            "技能原生获取状态回读不匹配: " .. id)
        if record.viewed ~= nil then
            assert(actual.viewed == record.viewed, "技能新获取标记发生意外变化: " .. id)
        end
    end
    assert(#current.records == count, "出现未预览的技能获取或删除")
    -- Untouched records must retain their relative order and fields, as well as membership.
    local old_order, new_order = {}, {}
    for _, record in ipairs(state.before.records) do
        if rollback or equipment_only or not state.touched[record.id] then old_order[#old_order + 1] = record.id end
    end
    for _, record in ipairs(current.records) do
        if rollback or equipment_only or not state.touched[record.id] then new_order[#new_order + 1] = record.id end
    end
    assert(table.concat(old_order, ",") == table.concat(new_order, ","), "其他技能的记录顺序意外变化")
    local equipment = access.equipment(state.actor)
    verify_equipment(rollback and state.equipment or state.expected_equipment, equipment)
    access.equipment_contract(state.actor, equipment)
    assert(access.guards(state.actor).fingerprint == state.guards.fingerprint,
        "职业经验、JP、职业资格或基础技能出现意外变化；停止修改并检查完整存档备份")
end

local function apply(state)
    for _, change in ipairs(state.actions) do
        local before = state.before.map[change.id]
        local existing = access.find_record(state.actor, change.id)
        if not change.learned or (before and before.enabled and change.level < before.level) then
            assert(existing, "待修改的预置记录已变化")
            -- The live game preallocates ID-indexed rows. Forgetting retains that shape
            -- and resets only this grade to the observed native disabled value.
            access.set(existing, "Level", change.level)
        else
            access.native_grant(state.actor, change.id, change.level)
        end
        local after = assert(access.find_record(state.actor, change.id), "原生获取接口没有产生学习记录")
        if before and access.boolean(access.get(after, "IsViewedNew")) ~= before.viewed then
            access.set(after, "IsViewedNew", before.viewed)
        end
    end
end

---Export a portable before-state; retained game references never reach JSON.
function M.backup(prepared)
    local result = {title = prepared.spec.title, kind = prepared.spec.kind, changes = prepared.spec.changes,
        skipped = prepared.spec.skipped, unequips = prepared.unequips, actors = {}}
    for _, state in ipairs(prepared.states) do
        result.actors[#result.actors + 1] = {role = state.actor.role, identity = state.actor.identity,
            records = portable_records(state.before), learned = portable_records(state.before, true),
            equipment = portable_equipment(state.equipment),
            protected_progress = state.guards}
    end
    return result
end

---Execute on the game update callback. Any failed verification restores both actors.
---@return boolean success
---@return string message
---@return boolean recovery_failed
function M.execute(prepared)
    if prepared.actual_writes + prepared.actual_slot_writes == 0 then return true, "目标状态已一致", false end
    for _, state in ipairs(prepared.states) do access.pin_records(state.before) end
    local ok, failure = xpcall(function()
        -- Clear every target actor's planned slots and verify all records/guards are
        -- still untouched before any learning write. Equipment and acquisition are
        -- one transaction; a partial clear must never be reported as a success.
        for _, state in ipairs(prepared.states) do
            for _, row in ipairs(state.unequips) do
                access.native_set_skill(state.actor, row.job, row.slot, state.none_id)
            end
        end
        if prepared.actual_slot_writes > 0 then
            for _, state in ipairs(prepared.states) do verify_state(state, false, true) end
        end
        for _, state in ipairs(prepared.states) do
            if #state.actions > 0 then
                apply(state)
            end
        end
        for _, state in ipairs(prepared.states) do verify_state(state, false) end
    end, debug.traceback)
    if ok then return true, "已修改 " .. prepared.actual_writes .. " 条技能状态"
        .. (prepared.actual_slot_writes > 0 and ("，自动卸下 " .. prepared.actual_slot_writes .. " 个技能槽") or ""), false end
    local recovery_errors = {}
    -- A native helper could affect the other actor even when it had no planned writes.
    -- Restore all target snapshots, then verify them again after both restorations.
    for i = #prepared.states, 1, -1 do
        local state = prepared.states[i]
        local restored, why = xpcall(function()
            access.restore(state.actor, state.before, state.equipment)
        end, debug.traceback)
        if not restored then recovery_errors[#recovery_errors + 1] = labels[state.actor.role] .. ": " .. tostring(why) end
    end
    for _, state in ipairs(prepared.states) do
        local restored, why = xpcall(function() verify_state(state, true) end, debug.traceback)
        if not restored then recovery_errors[#recovery_errors + 1] = labels[state.actor.role] .. ": " .. tostring(why) end
    end
    if #recovery_errors > 0 then
        return false, tostring(failure) .. "\n回滚未完成：\n" .. table.concat(recovery_errors, "\n"), true
    end
    return false, "操作失败，已恢复修改前状态：\n" .. tostring(failure), false
end

function M.state_export(actor, snapshot)
    snapshot = snapshot or access.records(actor)
    return {role = actor.role, identity = actor.identity, records = portable_records(snapshot),
        learned = portable_records(snapshot, true),
        learning_model = {valid = access.learning_model().valid,
            observations = access.learning_model().observations,
            unlearned_level = access.learning_model().unlearned_level},
        equipment = portable_equipment(access.equipment(actor)), protected_progress = access.guards(actor)}
end

return M
