-- SPDX-License-Identifier: MIT
-- The controller owns lifetime and update-stage dispatch; other modules never register callbacks.
local previous = rawget(_G, "DD2SkillStateManagerSession")
if previous then previous.active = false end
for _, name in ipairs({"access", "catalog", "operations", "diagnostics", "ui", "i18n", "progress", "progress_access"}) do
    package.loaded["DD2SkillStateManager/" .. name] = nil
end
local access = require("DD2SkillStateManager/access")
local catalog_api = require("DD2SkillStateManager/catalog")
local operations = require("DD2SkillStateManager/operations")
local progress = require("DD2SkillStateManager/progress")
local progress_access = require("DD2SkillStateManager/progress_access")
local handlers = {skills = operations, progress = progress}
local diagnostics = require("DD2SkillStateManager/diagnostics")
local ui = require("DD2SkillStateManager/ui")
local i18n = require("DD2SkillStateManager/i18n")
local settings_ok, settings = pcall(json.load_file, "DD2SkillStateManager/settings.json")
local language_mode = settings_ok and type(settings) == "table" and settings.language_mode
    or (previous and previous.language_mode) or "auto"
if language_mode ~= "auto" and language_mode ~= "zh" and language_mode ~= "en" then language_mode = "auto" end
local state = {active = true, visible = false, status = "等待进入存档", samples = {}, progress_samples = {},
    language_mode = language_mode, locale = i18n.resolve(language_mode), next_language_poll = 0,
    lock_reason = previous and previous.lock_reason, next_poll = 0, next_build = 0}
_G.DD2SkillStateManagerSession = state
local lock_files_ok, lock_files = pcall(fs.glob, [[DD2SkillStateManager[/\\]writer-lock\.json]])
if not lock_files_ok then
    state.lock_reason = state.lock_reason or "无法核验持久化修改锁，请检查数据目录权限"
elseif #lock_files > 0 then
    local lock = json.load_file("DD2SkillStateManager/writer-lock.json")
    if not lock or lock.locked ~= false then
        state.lock_reason = (lock and lock.reason) or "修改锁无法读取，请查看诊断并恢复完整存档"
    end
end

local function publish(message, failed, notice)
    local repeated = state.last_message == message
    state.status = message
    state.notice = notice or (failed and {key = "failed"} or nil)
    state.last_message = message
    if repeated then return end -- Repeated lifecycle failures must not fill the log every 0.5s.
    if failed then log.error("[DD2SkillStateManager] " .. message)
    else log.info("[DD2SkillStateManager] " .. message) end
end

---Read language in the update callback only; refresh text caches and cancel stale previews.
local function update_language(now, force)
    if force or now >= state.next_language_poll then
        state.next_language_poll = now + 2
        local before = state.game_language and state.game_language.name
        state.game_language = access.game_language()
        local locale = i18n.resolve(state.language_mode, state.game_language.name)
        if locale ~= state.locale or before ~= state.game_language.name then
            state.locale, state.catalog, state.preview, state.notice, state.next_build = locale, nil, nil, nil, 0
        end
    end
end

---Enqueue portable requests only; never let render callbacks mutate game objects.
local function submit(request)
    if state.pending then return end
    state.pending = request
end

local function sample()
    local collect_progress = state.progress_visible or next(state.progress_samples) == nil
    local result, progress_result, mapping_sources = {}, collect_progress and {} or state.progress_samples, {}
    for _, role in ipairs({"arisen", "pawn"}) do
        local ok, entry = xpcall(function()
            local actor = access.actor(role)
            local snapshot = access.records(actor)
            local data = operations.state_export(actor, snapshot)
            local contract, why = pcall(access.writer_contract, actor, snapshot)
            return {ok = true, data = data, writable = contract,
                contract_error = not contract and tostring(why) or nil}
        end, debug.traceback)
        result[role] = ok and entry or {ok = false, writable = false, error = tostring(entry)}
        -- One feature's signature failure must not conceal the other page's state.
        if state.catalog and collect_progress then
            local progress_ok, value = xpcall(function()
                local actor = access.actor(role)
                return progress.sample(actor, state.catalog, result[role].writable)
            end, debug.traceback)
            progress_result[role] = progress_ok and value or {ok = false, error = tostring(value)}
            if progress_ok then
                local jobs = {}
                for _, row in ipairs(value.data.jobs) do jobs[row.id] = row end
                mapping_sources[#mapping_sources + 1] = {role = role, data = {jobs = jobs, fields = value.data.fields}}
            end
        end
    end
    state.samples = result
    state.progress_samples = progress_result
    -- Mapping consumes portable rows; no game object reaches the UI cache.
    if state.catalog and collect_progress then
        state.qualification_mapping = progress_access.mapping(state.catalog, mapping_sources)
    end
end

local function fresh_catalog()
    assert(access.in_game(), "请进入存档正常游戏阶段")
    local catalog = catalog_api.build(state.locale)
    state.catalog = catalog
    return catalog
end

local function export_diagnostic(extra)
    local report = diagnostics.collect(state.catalog, state.status, state.lock_reason, state.locale)
    report.language = {mode = state.language_mode, effective = state.locale, game = state.game_language or access.game_language()}
    if extra then report.transaction = extra end
    state.last_file = diagnostics.write("diagnostic", report)
    return state.last_file
end

local function dispatch(request)
    if request.kind == "language" then
        assert(request.mode == "auto" or request.mode == "zh" or request.mode == "en", "未知界面语言")
        state.language_mode = request.mode
        state.catalog, state.preview, state.notice, state.next_build, state.next_poll = nil, nil, nil, 0, 0
        update_language(os.clock(), true)
        local saved, result = pcall(json.dump_file, "DD2SkillStateManager/settings.json",
            {schema = 1, language_mode = request.mode})
        if not saved or not result then
            publish("界面语言偏好保存失败：" .. tostring(result), true, {key = "language_not_saved"})
        end
        return
    end
    if request.kind == "diagnostic" then
        local path = export_diagnostic()
        publish("只读诊断已导出：" .. path, false, {key = "exported"})
        return
    end
    if request.kind == "refresh" then
        state.preview, state.catalog, state.next_build = nil, nil, 0
        local catalog = fresh_catalog()
        sample()
        publish("目录已刷新：" .. #catalog.order .. " 项武器主动技能。", false, {key = "refreshed"})
        return
    end
    assert(not state.lock_reason, "修改已锁定：" .. tostring(state.lock_reason))
    local catalog = fresh_catalog() -- Re-check parameter tables and ownership at every button action.
    if request.kind ~= "execute" then
        local domain = progress.accepts(request.kind) and "progress" or "skills"
        local handler = handlers[domain]
        local spec
        if domain == "progress" then
            spec = handler.specification(catalog, request.kind, request.target, request.job_id, request.value)
        else spec = handler.specification(catalog, request.kind, request.skill_id, request.level, request.job_id) end
        local prepared = handler.prepare(catalog, spec)
        state.preview = {requested_spec = spec, fingerprint = prepared.fingerprint,
            domain = domain,
            title = spec.title, rows = prepared.preview, actual_writes = prepared.actual_writes,
            kind = request.kind, skill_id = request.skill_id, job_id = request.job_id,
            unequips = prepared.unequips, actual_slot_writes = prepared.actual_slot_writes,
            requested_count = #spec.changes + #spec.skipped, accepted_count = #prepared.spec.changes,
            skipped = prepared.spec.skipped, has_pawn = #prepared.states == 2}
        -- The preview contains no game objects. Prepared references die at callback end.
        publish("预览已生成，请检查逐项变更与跳过原因。", false)
        return
    end
    local preview = assert(state.preview, "没有待确认的预览")
    state.preview = nil -- A confirmation can execute at most once, even if an error occurs.
    local handler = assert(handlers[preview.domain], "未知事务类别")
    local prepared = handler.prepare(catalog, preview.requested_spec)
    assert(prepared.fingerprint == preview.fingerprint, "预览后状态已变化，已取消；请重新预览")
    if prepared.actual_writes + prepared.actual_slot_writes == 0 then
        publish("无可变更记录；目标已一致或均被规则跳过。", false, {key = "no_changes"})
        return
    end
    local before = handler.backup(prepared)
    state.last_file = diagnostics.write("before", before)
    local backup_file = state.last_file
    -- Disk I/O precedes mutation. Reacquire actors instead of trusting retained references.
    local final_catalog = fresh_catalog()
    local final = handler.prepare(final_catalog, preview.requested_spec)
    assert(final.fingerprint == prepared.fingerprint, "保存快照期间状态改变，已取消；请重新预览")
    local success, message, recovery_failed = handler.execute(final, final_catalog)
    if recovery_failed then
        state.lock_reason = "事务回滚失败。停止修改；退出游戏前不要手动保存，请恢复完整存档备份。"
        -- Session lock works even if the disk is unavailable. Persist it for script reload/restart.
        pcall(json.dump_file, "DD2SkillStateManager/writer-lock.json", {locked = true, reason = state.lock_reason})
        pcall(export_diagnostic, {before_file = backup_file, error = message, before = before})
    end
    local journal_ok, journal_file = pcall(diagnostics.write, "operation", {
        success = success, message = message, recovery_failed = recovery_failed, before_file = backup_file,
        domain = preview.domain, kind = final.spec.kind, target = final.spec.target, job_id = final.spec.job_id, value = final.spec.value,
        changes = final.spec.changes, skipped = final.spec.skipped, unequips = final.unequips,
        actual_writes = final.actual_writes, actual_slot_writes = final.actual_slot_writes})
    if journal_ok then state.last_file = journal_file
    else message = message .. "\n操作日志写入失败：" .. tostring(journal_file) end
    sample()
    local notice = success and (preview.domain == "progress" and {key = "progress_done", args = {final.actual_writes}}
        or {key = "done", args = {final.actual_writes, final.actual_slot_writes}})
        or {key = recovery_failed and "recovery_failed" or "restored"}
    if not journal_ok and success then notice = {key = "journal_failed"} end
    publish(message, not success, notice)
end

local function lifecycle(now)
    update_language(now)
    if not access.in_game() then
        if state.catalog or state.token then
            state.catalog, state.preview, state.token, state.samples = nil, nil, nil, {}
            state.progress_samples, state.qualification_mapping = {}, nil
            publish("等待进入存档；已释放目录和预览。", false)
        end
        return
    end
    local token = access.address(access.scene())
    for _, role in ipairs({"arisen", "pawn"}) do
        local ok, actor = pcall(access.actor, role)
        token = token .. "|" .. (ok and actor.identity or (role .. ":unavailable"))
    end
    if token ~= state.token then
        state.token, state.catalog, state.preview, state.next_build = token, nil, nil, 0
        state.progress_samples, state.qualification_mapping = {}, nil
    end
    if not state.catalog and now >= state.next_build then
        state.next_build = now + 3
        local ok, catalog = xpcall(function() return catalog_api.build(state.locale) end, debug.traceback)
        if ok then
            state.catalog = catalog
            publish("目录就绪：" .. #catalog.order .. " 项；选择职业与技能后预览操作。", false, state.notice)
        else state.status = "只读等待：" .. tostring(catalog) end
    end
    if state.visible or not state.samples.arisen then sample() end
end

re.on_pre_application_entry("UpdateBehavior", function()
    if not state.active then return end
    local ok, why = xpcall(function()
        local now = os.clock()
        if now >= state.next_poll then
            state.next_poll = now + 0.5
            lifecycle(now)
        end
        if state.pending then
            local request = state.pending
            state.pending = nil
            dispatch(request)
        end
    end, debug.traceback)
    if not ok then
        state.preview = nil
        state.next_poll = os.clock() + 3 -- Back off until components/actors become usable.
        local reason = tostring(why):match("^[^\r\n]*") or ""
        local notice = {key = "failed"}
        for _, entry in ipairs({{"预览后状态已变化", "preview_changed"}, {"保存快照期间状态改变", "save_changed"},
            {"职业正在使用", "current_job_blocked"}, {"基础职业不可锁定", "basic_lock_blocked"},
            {"职业资格位图无法", "mapping_unknown"}, {"主随从不能使用此职业", "pawn_job_blocked"},
            {"JP 需要为有效", "jp_invalid"}, {"目标超过游戏最高", "rank_invalid"},
            {"主随从当前不可访问", "pawn_missing"}, {"主随从尚未载入", "pawn_missing"},
            {"请进入存档正常游戏阶段", "in_game_required"}, {"请在存档正常游戏阶段操作", "in_game_required"}}) do
            if reason:find(entry[1], 1, true) then notice.key = entry[2]; break end
        end
        publish("已停止本次请求：" .. tostring(why), true, notice)
    end
end)

re.on_draw_ui(function()
    if state.active then ui.draw(state, submit) end
end)
