-- SPDX-License-Identifier: MIT
-- Render portable controller data only. Every button submits an update-stage request.
local i18n = require("DD2SkillStateManager/i18n")
local M = {}
local language = "en"
local font, font_attempted
local ui = {job_index = 1, query = "", skill_id = nil, level_index = 1, page = 1,
    view_index = 1, target_index = 1, vocation_index = 1, glyph_widths = {}}
local accent = 0xFFE6C68A
local warning = 0xFFF1C75B
-- This REFramework binding exposes numeric ImGuiCol values, not a color enum.
-- Verified against its pinned Dear ImGui 1.92.0 header (85b2fe848619...).
local style_colors = {text = 0, button = 21, hovered = 22, active = 23}
-- PushStyleColor uses native ABGR; text_colored uses ARGB. Keep them separate.
local button_colors = {
    confirm = {0xFF347D25, 0xFF439D32, 0xFF29681F},
    danger = {0xFF3434A1, 0xFF4444C3, 0xFF292986},
    action = {0xFF98632A, 0xFFBA7B37, 0xFF805323},
}

local function t(key, ...) return i18n.text(language, key, ...) end
local function widget(key, id) return t(key) .. "###" .. id end
local function unit() return ui.line_height or math.max(1, imgui.calc_text_size("M").y) end
local function label_width()
    if not ui.label_measured then
        local width = 0
        for _, key in ipairs({"language", "page", "actor", "job", "target_level", "jp_balance", "jp_target"}) do
            width = math.max(width, imgui.calc_text_size(t(key)).x)
        end
        ui.label_measured = width
    end
    local available = imgui.get_window_size().x - imgui.get_cursor_pos().x - unit() * 1.4
    return math.min(ui.label_measured + unit() * 0.6, math.max(unit() * 2, available * 0.4))
end
local function role_width()
    if not ui.role_measured then ui.role_measured = math.max(imgui.calc_text_size(t("arisen")).x, imgui.calc_text_size(t("pawn")).x) end
    local measured = ui.role_measured + unit() * 0.6
    local available = imgui.get_window_size().x - imgui.get_cursor_pos().x - unit() * 1.4
    return math.min(measured, math.max(unit() * 2, available * 0.3))
end
local function grade(learned, level) return learned and t("level", level) or t("not_learned") end

local function content_width()
    return math.max(unit() * 3, imgui.get_window_size().x - imgui.get_cursor_pos().x - unit() * 1.4)
end

---Wrap localized text to the current panel width without splitting UTF-8 characters.
---Measure UTF-8 glyphs at the current font size; cache widths until the size changes.
local function text(value, width, color)
    local line, used = {}, 0
    local limit = width or content_width()
    for _, code in utf8.codes(tostring(value or "")) do
        local weight = ui.glyph_widths[code]
        if not weight then weight = imgui.calc_text_size(utf8.char(code)).x; ui.glyph_widths[code] = weight end
        if code == 10 or (used > 0 and used + weight > limit) then
            if color then imgui.text_colored(table.concat(line), color) else imgui.text(table.concat(line)) end
            line, used = {}, 0
        end
        if code ~= 10 then line[#line + 1], used = utf8.char(code), used + weight end
    end
    if #line > 0 then
        if color then imgui.text_colored(table.concat(line), color) else imgui.text(table.concat(line)) end
    end
end

---Apply local button colors and always unwind, including a drawing error.
local function button(key, id, tone)
    local colors = button_colors[tone]
    if not colors then return imgui.button(widget(key, id)) end
    local count = 0
    local ok, result = xpcall(function()
        local function push(index, color)
            -- sol's integer overload expects a signed Int32; ImGui casts to U32.
            imgui.push_style_color(index, color >= 0x80000000 and color - 0x100000000 or color)
            count = count + 1
        end
        push(style_colors.text, 0xFFFFFFFF)
        push(style_colors.button, colors[1]); push(style_colors.hovered, colors[2]); push(style_colors.active, colors[3])
        return imgui.button(widget(key, id))
    end, debug.traceback)
    if count > 0 then imgui.pop_style_color(count) end
    if not ok then error(result, 0) end
    return result
end

-- Every helper unwinds its ImGui stack before propagating an error to the controller.
local function disabled(value, draw)
    imgui.begin_disabled(value)
    local ok, why = xpcall(draw, debug.traceback)
    imgui.end_disabled()
    if not ok then error(why, 0) end
end

local function table_view(id, columns, headers, draw)
    local flags = imgui.TableFlags.SizingStretchProp | imgui.TableFlags.NoSavedSettings
    if headers then flags = flags | imgui.TableFlags.RowBg | imgui.TableFlags.BordersInnerH end
    if not imgui.begin_table(id, #columns, flags) then return end
    local ok, why = xpcall(function()
        for _, column in ipairs(columns) do
            imgui.table_setup_column(column[1], column[2] and imgui.ColumnFlags.WidthFixed
                or imgui.ColumnFlags.WidthStretch, column[2] or 1.0)
        end
        if headers then imgui.table_headers_row() end
        draw()
    end, debug.traceback)
    imgui.end_table()
    if not ok then error(why, 0) end
end

local function field(label, draw)
    imgui.table_next_row()
    imgui.table_set_column_index(0)
    text(label, math.max(unit(), label_width() - unit() * 0.5))
    imgui.table_set_column_index(1)
    imgui.set_next_item_width(-1)
    draw()
end

---Keep related buttons on one row only when their current text sizes fit.
local function adjacent(first, second)
    if imgui.calc_text_size(t(first)).x + imgui.calc_text_size(t(second)).x + unit() * 2.5 < content_width() then imgui.same_line() end
end

local function heading(label)
    imgui.separator()
    imgui.text_colored(t(label), accent)
end

local function reset_selection(state, id)
    ui.skill_id, ui.level_index, ui.page = id, 1, 1
    state.preview = nil -- Never leave a confirmation for a previously selected skill.
    local skill = state.catalog and state.catalog.by_id[id]
    local sample = state.samples.arisen
    if skill and sample and sample.ok then
        for _, row in ipairs(sample.data.records) do
            if row.id == id and row.enabled then
                for index, level in ipairs(skill.levels) do
                    if level == row.level then ui.level_index = index end
                end
                break
            end
        end
    end
end

local function status_for(state, role, id)
    local sample = state.samples[role]
    if not sample or not sample.ok then return t("not_loaded") end
    if not sample.writable then return t("read_only") end
    for _, row in ipairs(sample.data.records) do
        if row.id == id then return row.enabled and t("learned", row.level) or t("not_learned") end
    end
    return t("not_learned")
end

local function can_edit(state, skill)
    if state.lock_reason or state.pending or not skill.valid then return false end
    local arisen, pawn = state.samples.arisen, state.samples.pawn
    return arisen and arisen.writable and (skill.target ~= "both" or (pawn and pawn.writable))
end

local function for_job(variant, job)
    if variant.job == job then return variant end
    for _, other in ipairs(variant.alternates or {}) do if other.job == job then return other end end
    return variant
end

local function preview_change(item, row)
    if not row.writes then return t("unchanged") end
    if item.domain == "progress" then
        local function value(v)
            if row.field == "qualification" then return t(v and "unlocked" or "locked") end
            if row.field == "vocation_rank_label" then return t("level", v) end
            return tostring(v)
        end
        return value(row.before) .. " → " .. value(row.after)
    end
    return grade(row.before_learned, row.before_level) .. " → " .. grade(row.after_learned, row.after_level)
end

local function preview_label(state, item, row)
    if item.domain ~= "progress" then return row.name end
    local job = row.job_id and state.catalog.jobs[row.job_id]
    return t(row.field) .. (job and (" · " .. job.name) or "")
end

local function preview(state, submit)
    local item = state.preview
    if not item then return end
    heading("confirm_heading")
    if item.domain == "progress" then text(t(item.kind))
    elseif item.kind == "all" then text(t("learn_all"))
    elseif item.kind == "job_all" then
        text(t("job_named", state.catalog.jobs[item.job_id].name))
    else
        local skill = state.catalog.by_id[item.skill_id]
        text(t(item.kind == "delete" and "delete_named" or "set_named", skill.name))
    end
    local count = t(item.domain == "progress" and "progress_count" or "state_count", item.actual_writes)
    if item.actual_slot_writes > 0 then count = count .. t("unequip_count", item.actual_slot_writes) end
    if #item.skipped > 0 then count = count .. t("skipped_count", #item.skipped) end
    text(count)
    local pages = math.max(1, math.ceil(#item.rows / 10))
    ui.page = math.min(ui.page, pages)
    local available, change_width = content_width(), 0
    for _, row in ipairs(item.rows) do change_width = math.max(change_width, imgui.calc_text_size(preview_change(item, row)).x) end
    change_width = math.min(change_width + unit(), available * 0.42)
    local compact = available < role_width() + change_width + unit() * 8
    if compact then
        for index = (ui.page - 1) * 10 + 1, math.min(ui.page * 10, #item.rows) do
            local row = item.rows[index]
            text(t(row.role) .. " · " .. preview_label(state, item, row), available)
            text(preview_change(item, row), available)
            imgui.separator()
        end
    else table_view("DD2SSMPreview", {{t("actor"), role_width()},
        {t(item.domain == "progress" and "state" or "skill")}, {t("change"), change_width}}, true, function()
        for index = (ui.page - 1) * 10 + 1, math.min(ui.page * 10, #item.rows) do
            local row = item.rows[index]
            imgui.table_next_row()
            imgui.table_set_column_index(0); text(t(row.role), role_width())
            imgui.table_set_column_index(1)
            text(preview_label(state, item, row),
                math.max(unit() * 3, available - role_width() - change_width - unit() * 2))
            imgui.table_set_column_index(2)
            text(preview_change(item, row), change_width - unit() * 0.5)
        end
    end) end
    if pages > 1 then
        disabled(ui.page == 1, function()
            if imgui.small_button(widget("previous_page", "DD2SSMPrev")) then ui.page = ui.page - 1 end
        end)
        imgui.same_line(); imgui.text(ui.page .. " / " .. pages); imgui.same_line()
        disabled(ui.page == pages, function()
            if imgui.small_button(widget("next_page", "DD2SSMNext")) then ui.page = ui.page + 1 end
        end)
    end
    if #item.unequips > 0 and imgui.collapsing_header(widget("unequip_list", "DD2SSMUnequips")) then
        for _, row in ipairs(item.unequips) do
            text(t(row.role) .. " · " .. row.job_name .. " · " .. t("slot", row.slot) .. " · " .. row.name)
        end
    end
    if #item.skipped > 0 and imgui.collapsing_header(widget("skipped_list", "DD2SSMSkipped")) then
        for _, row in ipairs(item.skipped) do
            text((row.role and (t(row.role) .. " · ") or "") .. row.name .. ": " .. i18n.skip(language, row))
        end
    end
    text(t("pending_confirmation"), nil, warning)
    disabled(state.pending ~= nil or state.lock_reason ~= nil, function()
        if button("confirm", "DD2SSMExecute", "confirm") then submit({kind = "execute"}) end
    end)
    adjacent("confirm", "cancel")
    if button("cancel", "DD2SSMCancel", "danger") then state.preview = nil end
end

local function selected_skill(state, submit, job, skill)
    heading("current_state")
    table_view("DD2SSMState", {{t("actor"), role_width() + unit() * 0.5}, {t("state")}}, true, function()
        for _, role in ipairs(skill.target == "both" and {"arisen", "pawn"} or {"arisen"}) do
            imgui.table_next_row()
            imgui.table_set_column_index(0); text(t(role), role_width())
            imgui.table_set_column_index(1); imgui.text(status_for(state, role, skill.id))
        end
    end)
    local references = {}
    for _, role in ipairs(skill.target == "both" and {"arisen", "pawn"} or {"arisen"}) do
        local sample = state.samples[role]
        if sample and sample.ok then
            for _, row in ipairs(sample.data.equipment) do
                if row.id == skill.id then
                    local palette = state.catalog.jobs[row.job]
                    references[#references + 1] = t(role) .. " · "
                        .. (palette and palette.name or t("fallback_job", row.job)) .. " · " .. t("slot", row.slot + 1)
                end
            end
        end
    end
    if #references > 0 then
        text(t("equipped"))
        if imgui.collapsing_header(widget("equipment_locations", "DD2SSMEquipped")) then
            for _, reference in ipairs(references) do text(reference) end
        end
    end
    if not skill.valid then text(t("unavailable_skill")) end
    if #skill.levels == 0 then return end
    local options = {}
    for _, level in ipairs(skill.levels) do
        options[#options + 1] = t("level", level) .. " · " .. for_job(skill.variants[level], job.id).name
    end
    if not skill.levels[ui.level_index] then ui.level_index = 1 end
    heading("settings")
    table_view("DD2SSMLevelForm", {{t("target_level"), label_width()}, {t("selection")}}, false, function()
        field(t("target_level"), function()
            local changed, index = imgui.combo("##DD2SSMLevel", ui.level_index, options)
            if changed then ui.level_index, state.preview = index, nil end
        end)
    end)
    local variant = for_job(skill.variants[skill.levels[ui.level_index]], job.id)
    if variant.description ~= "" and imgui.collapsing_header(widget("description", "DD2SSMDescription")) then text(variant.description) end
    local owned = not variant.expansion or state.catalog.expansion_owned == true
    if not owned then text(t("requires_expansion")) end
    disabled(not can_edit(state, skill), function()
        disabled(not owned, function()
            if button("set", "DD2SSMSet", "action") then
                ui.page = 1
                submit({kind = "set", skill_id = skill.id, level = variant.level})
            end
        end)
        adjacent("set", "delete")
        if button("delete", "DD2SSMDelete", "danger") then
            ui.page = 1
            submit({kind = "delete", skill_id = skill.id})
        end
    end)
end

local function tools(state, submit)
    if imgui.collapsing_header(widget("tools", "DD2SSMTools")) then
        disabled(state.pending ~= nil, function()
            if imgui.button(widget("refresh", "DD2SSMRefresh")) then submit({kind = "refresh"}) end
            imgui.same_line()
            if imgui.button(widget("diagnostic", "DD2SSMDiag")) then submit({kind = "diagnostic"}) end
        end)
    end
end

local function progress_row(state, role, id)
    local sample = state.progress_samples[role]
    if sample and sample.ok then
        for _, row in ipairs(sample.data.jobs) do if row.id == id then return row end end
    end
end

---Always compare both actors in read-only views, independently of edit scope.
local function actor_table(id, draw)
    table_view(id, {{t("actor"), role_width()}, {t("state")}}, true, function()
        for _, role in ipairs({"arisen", "pawn"}) do
            imgui.table_next_row(); imgui.table_set_column_index(0); text(t(role), role_width())
            imgui.table_set_column_index(1)
            draw(role)
        end
    end)
end

---Display current vocation information without mixing selected-job edit controls.
local function current_progress(state)
    local catalog = state.catalog
    heading("current_state")
    actor_table("DD2SSMCurrentProgress", function(role)
        local sample = state.progress_samples[role]
        if not sample or not sample.ok then text(t("not_loaded")); return end
        local id = sample.data.fields.CurrentJob
        local job, row = catalog.jobs[id], progress_row(state, role, id)
        text(t("current_job") .. ": " .. (job and job.name or t("fallback_job", id)))
        text(t("vocation_rank_label") .. ": " .. (row and row.rank_ok and tostring(row.rank) or t("read_only")))
        text(t("jp_balance") .. ": " .. tostring(sample.data.fields.ConsumableExp))
    end)
end

---Use selected progress targets only for requests; skill synchronization is separate.
local function progress_contents(state, submit)
    local catalog = state.catalog
    local targets, labels = {"arisen", "pawn", "both"}, {}
    for _, id in ipairs(catalog.job_order) do labels[#labels + 1] = catalog.jobs[id].name end
    if not catalog.job_order[ui.vocation_index] then ui.vocation_index = 1 end
    current_progress(state)
    heading("vocation_edit")
    table_view("DD2SSMProgressSelection", {{t("actor"), label_width()}, {t("state")}}, false, function()
        field(t("actor"), function()
            local changed, index = imgui.combo("##DD2SSMProgressTarget", ui.target_index, {t("arisen"), t("pawn"), t("both")})
            if changed then ui.target_index, ui.vocation_rank_index, ui.jp_text, ui.page, state.preview = index, nil, nil, 1, nil end
        end)
        field(t("job"), function()
            local changed, index = imgui.combo("##DD2SSMProgressJob", ui.vocation_index, labels)
            if changed then ui.vocation_index, ui.vocation_rank_index, ui.page, state.preview = index, nil, 1, nil end
        end)
    end)
    local target, id = targets[ui.target_index], catalog.job_order[ui.vocation_index]
    local job = catalog.jobs[id]
    local exclusive = job.number >= 7 and job.number <= 10
    local known = job.number >= 1 and job.number <= 10
    local roles = target == "both" and {"arisen", "pawn"} or {target}
    local job_roles = exclusive and target == "both" and {"arisen"} or roles
    actor_table("DD2SSMSelectedVocation", function(role)
        local sample, row = state.progress_samples[role], progress_row(state, role, id)
        if not sample or not sample.ok then text(t("not_loaded")); return end
        if exclusive and role == "pawn" then text(t("not_applicable")); return end
        text(t("qualification") .. ": " .. (row and row.qualified ~= nil and t(row.qualified and "unlocked" or "locked") or t("read_only")))
        text(t("vocation_rank_label") .. ": " .. (row and row.rank_ok and tostring(row.rank) or t("read_only")))
    end)
    if exclusive then text(t(target == "pawn" and "pawn_job_blocked" or "arisen_only")) end
    local unavailable = not known or (exclusive and target == "pawn")
    local can_qualify, can_rank, current, maximum = not unavailable, not unavailable, false, nil
    for _, role in ipairs(job_roles) do
        local sample, row = state.progress_samples[role], progress_row(state, role, id)
        local writable = sample and sample.ok and sample.protected_ok
        can_qualify = can_qualify and writable and sample.data.capabilities.qualification.ok and row and row.qualified ~= nil
        can_rank = can_rank and writable and sample.data.capabilities.rank.ok and row and row.rank_ok
        if sample and sample.ok and sample.data.fields.CurrentJob == id then current = true end
        if row and row.rank_ok then maximum = math.min(maximum or row.maximum, row.maximum) end
    end
    local busy = state.pending ~= nil or state.lock_reason ~= nil
    disabled(busy or not can_qualify, function()
        if button("vocation_unlock", "DD2SSMUnlockVocation", "action") then
            ui.page = 1; submit({kind = "vocation_unlock", target = target, job_id = id})
        end
    end)
    adjacent("vocation_unlock", "vocation_lock")
    local basic = job.number >= 1 and job.number <= 4
    local mapping_ok = state.qualification_mapping and state.qualification_mapping.known
    disabled(busy or not can_qualify or basic or current or not mapping_ok, function()
        if button("vocation_lock", "DD2SSMLockVocation", "danger") then
            ui.page = 1; submit({kind = "vocation_lock", target = target, job_id = id})
        end
    end)
    if can_qualify and not basic and current then text(t("current_job_blocked")) end
    if can_qualify and basic then text(t("basic_lock_blocked")) end
    if can_qualify and not basic and not current and not mapping_ok then text(t("mapping_unknown")) end
    if maximum and can_rank then
        local options = {}
        for rank = 1, maximum do options[#options + 1] = t("level", rank) end
        local row = progress_row(state, job_roles[1], id)
        ui.vocation_rank_index = math.min(ui.vocation_rank_index or row.rank, maximum)
        table_view("DD2SSMRankInput", {{t("target_level"), label_width()}, {t("state")}}, false, function()
            field(t("target_level"), function()
                local changed, index = imgui.combo("##DD2SSMVocationRank", ui.vocation_rank_index, options)
                if changed then ui.vocation_rank_index, state.preview = index, nil end
            end)
        end)
    end
    disabled(busy or not can_rank, function()
        if button("vocation_rank", "DD2SSMSetVocationRank", "action") then
            ui.page = 1; submit({kind = "vocation_rank", target = target, job_id = id, value = ui.vocation_rank_index})
        end
    end)
    if not can_rank and not can_qualify and not unavailable then text(t("progress_unavailable")) end
    -- All-vocation unlock uses the character selector but ignores the vocation selector.
    -- Both requires both actors; exclusive vocations are skipped for the Pawn.
    local can_unlock_all, can_jp = true, true
    for _, role in ipairs(roles) do
        local sample = state.progress_samples[role]
        local writable = sample and sample.ok and sample.protected_ok
        can_unlock_all = can_unlock_all and writable and sample.data.capabilities.qualification.ok
        can_jp = can_jp and writable and sample.data.capabilities.jp.ok
    end
    disabled(busy or not can_unlock_all, function()
        if button("vocation_unlock_all", "DD2SSMUnlockAllVocations", "action") then
            ui.page = 1; submit({kind = "vocation_unlock_all", target = target})
        end
    end)
    heading("jp_edit")
    for _, role in ipairs(roles) do
        local sample = state.progress_samples[role]
        if sample and sample.ok then
            text(t(role) .. ": " .. tostring(sample.data.fields.ConsumableExp))
            if ui.jp_text == nil then ui.jp_text = tostring(sample.data.fields.ConsumableExp) end
        else text(t(role) .. ": " .. t("not_loaded")) end
    end
    ui.jp_text = ui.jp_text or "0"
    table_view("DD2SSMJPInput", {{t("jp_target"), label_width()}, {t("state")}}, false, function()
        field(t("jp_target"), function()
            local changed, value = imgui.input_text("##DD2SSMJP", ui.jp_text)
            if changed then ui.jp_text, state.preview = value, nil end
        end)
    end)
    local digits = ui.jp_text:match("^%s*(%d+)%s*$")
    local parsed = digits and tonumber(digits)
    local amount = parsed and math.tointeger(parsed)
    local valid = amount and amount >= 0 and amount <= 2147483647
    if not valid then text(t("jp_invalid")) end
    disabled(busy or not can_jp or not valid, function()
        if button("jp", "DD2SSMSetJP", "action") then ui.page = 1; submit({kind = "jp", target = target, value = amount}) end
    end)
end

local function contents(state, submit)
    -- A manual override remains usable even if the optional game-language getter fails.
    local modes = {"auto", "zh", "en"}
    local mode_index = state.language_mode == "zh" and 2 or (state.language_mode == "en" and 3 or 1)
    table_view("DD2SSMLanguageForm", {{t("language"), label_width()}, {t("selection")}}, false, function()
        field(t("language"), function()
            disabled(state.pending ~= nil, function()
                local changed, index = imgui.combo("##DD2SSMLanguage", mode_index, {t("auto"), "中文", "English"})
                if changed then submit({kind = "language", mode = modes[index]}) end
            end)
        end)
    end)
    if state.lock_reason then text(t("editing_locked"))
    elseif state.notice then text(i18n.notice(language, state.notice)) end
    if state.font_warning then imgui.text("Chinese font unavailable. Reload scripts after reinstalling the font.") end
    table_view("DD2SSMPageForm", {{t("page"), label_width()}, {t("state")}}, false, function()
        field(t("page"), function()
            local changed, index = imgui.combo("##DD2SSMPage", ui.view_index, {t("skills_page"), t("progress_page")})
            if changed then ui.view_index, state.preview = index, nil end
        end)
    end)
    if state.preview then text(t("pending_confirmation"), nil, warning) end
    local catalog = state.catalog
    if not catalog then
        text(t("waiting"))
        tools(state, submit)
        return
    end
    if ui.view_index == 2 then
        progress_contents(state, submit)
        preview(state, submit)
        tools(state, submit)
        return
    end
    local job_labels = {}
    for index, id in ipairs(catalog.job_order) do job_labels[index] = catalog.jobs[id].name end
    if not catalog.job_order[ui.job_index] then ui.job_index = 1 end
    local job = catalog.jobs[catalog.job_order[ui.job_index]]
    heading("selection")
    table_view("DD2SSMSelection", {{t("selection"), label_width()}, {t("skill")}}, false, function()
        field(t("job"), function()
            local changed, index = imgui.combo("##DD2SSMJob", ui.job_index, job_labels)
            if changed then ui.job_index = index; reset_selection(state, nil) end
        end)
        job = catalog.jobs[catalog.job_order[ui.job_index]]
        field(t("search"), function()
            local changed, query = imgui.input_text("##DD2SSMSearch", ui.query)
            if changed then ui.query, state.preview = query, nil end
        end)
        local visible, options = {}, {}
        for _, id in ipairs(job.skills) do
            local skill = catalog.by_id[id]
            local matched = ui.query == "" or tostring(id):find(ui.query, 1, true)
            for _, level in ipairs(skill.levels) do
                if for_job(skill.variants[level], job.id).name:lower():find(ui.query:lower(), 1, true) then matched = true end
            end
            if matched then
                visible[#visible + 1] = id
                local variant = skill.variants[skill.levels[1]]
                options[#options + 1] = (variant and for_job(variant, job.id).name or skill.name)
                    .. (skill.valid and "" or t("read_only_suffix"))
            end
        end
        local selected_index, found = 1, false
        for index, id in ipairs(visible) do if id == ui.skill_id then selected_index, found = index, true end end
        if not found and ui.skill_id ~= visible[1] then reset_selection(state, visible[1]) end
        field(t("select_skill"), function()
            if #visible == 0 then imgui.text(t("no_match")); return end
            local changed, index = imgui.combo("##DD2SSMSkill", selected_index, options)
            if changed then reset_selection(state, visible[index]) end
        end)
    end)
    local skill = catalog.by_id[ui.skill_id]
    if skill then selected_skill(state, submit, job, skill) end
    preview(state, submit)
    imgui.separator()
    if imgui.collapsing_header(widget("bulk", "DD2SSMBulk")) then
        disabled(state.pending ~= nil or state.lock_reason ~= nil, function()
            if button("learn_job", "DD2SSMJobAll", "action") then
                ui.page = 1; submit({kind = "job_all", job_id = job.id})
            end
            if button("learn_all", "DD2SSMAll", "action") then ui.page = 1; submit({kind = "all"}) end
        end)
    end
    tools(state, submit)
end

---Draw inside REFramework's Script Generated UI; errors are exported, not rendered as traces.
function M.draw(state, submit)
    language = state.locale or "en"
    if language ~= ui.last_language then
        -- A translated name search must not hide the selected ID after a switch.
        ui.query, ui.page, ui.last_language = "", 1, language
        ui.label_measured, ui.role_measured = nil, nil
    end
    local size_ok, size = pcall(imgui.get_default_font_size)
    if not size_ok or type(size) ~= "number" or size <= 0 then size = unit() end
    if ui.font_size ~= size then
        ui.font_size, ui.glyph_widths, ui.label_measured, ui.role_measured = size, {}, nil, nil
    end
    if not font_attempted then
        font_attempted = true
        local ok, loaded = pcall(imgui.load_font, "DD2SkillStateManager-CJK.otf", size)
        if ok and loaded then font = loaded else state.font_warning = tostring(loaded) end
    end
    if font then imgui.push_font(font, size) end
    ui.line_height = math.max(1, imgui.calc_text_size("M").y)
    local opened = imgui.tree_node(widget("title", "DD2SkillStateManager"))
    state.visible = opened
    state.progress_visible = opened and ui.view_index == 2
    local ok, why = true, nil
    if opened then
        ok, why = xpcall(function() contents(state, submit) end, debug.traceback)
        imgui.tree_pop()
    end
    if font then imgui.pop_font() end
    if not ok then
        state.status, state.notice = "界面错误：" .. tostring(why), {key = "ui_error"}
        if state.last_ui_error ~= tostring(why) then log.error("[DD2SkillStateManager] " .. state.status) end
        state.last_ui_error = tostring(why)
    end
end

return M

