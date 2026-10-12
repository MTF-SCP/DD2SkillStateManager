-- SPDX-License-Identifier: MIT
-- Presentation-only localization. Keys never encode skill IDs, levels or write rules.
local M = {}

M.strings = {
    en = {
        title = "DD2 Skill Controller", language = "Language", auto = "Auto (game language)",
        page = "Page", skills_page = "Skills", progress_page = "Vocations & JP", both = "Both",
        progress_selection = "Vocation", qualification = "Qualification", unlocked = "Unlocked", locked = "Locked",
        vocation_edit = "Edit selected vocation", jp_edit = "Edit JP", jp_target = "Target JP", vocation_unlock_all = "Unlock all vocations",
        pending_confirmation = "These changes have not been applied. Confirm to apply them.",
        not_applicable = "Arisen only", skip_pawn_job = "%s cannot use this vocation.",
        skip_unknown_job = "Vocation ownership could not be verified.",
        vocation_rank_label = "Vocation rank", current_job = "Current vocation", jp_balance = "JP balance",
        vocation_unlock = "Unlock vocation", vocation_lock = "Lock vocation", vocation_rank = "Set vocation rank", jp = "Set JP",
        progress_count = "%d progress values", progress_done = "Updated %d progress values.",
        current_job_blocked = "This vocation is in use. Change vocation in game before locking it.",
        basic_lock_blocked = "Basic vocations remain available and cannot be locked.",
        mapping_unknown = "Locking is unavailable until the qualification bitmap can be verified. Export diagnostics.",
        pawn_job_blocked = "This vocation is available to the Arisen only.",
        arisen_only = "This vocation affects the Arisen only.", progress_unavailable = "Progress editing unavailable. Export diagnostics.",
        jp_invalid = "Enter a whole number from 0 to 2147483647.", rank_invalid = "Select a valid vocation rank.",
        arisen = "Arisen", pawn = "Main Pawn", level = "Level %d", learned = "Learned · Level %d",
        not_learned = "Not learned", not_loaded = "Not available", read_only = "Read only",
        confirm_heading = "Review changes", state_count = "%d skill records",
        unequip_count = " · %d slots to unequip", skipped_count = " · %d items skipped",
        actor = "Character", skill = "Skill", change = "Change", unchanged = "Unchanged",
        previous_page = "Previous", next_page = "Next", unequip_list = "Slots to unequip",
        skipped_list = "Skipped items", confirm = "Confirm changes", cancel = "Discard changes",
        current_state = "Current state", state = "State", job = "Vocation", search = "Search",
        select_skill = "Select skill", settings = "Set skill", target_level = "Target level",
        description = "Skill description", equipped = "Equipped · automatically unequipped when changed",
        equipment_locations = "Equipped slots", slot = "Slot %d", fallback_job = "Vocation %d",
        unavailable_skill = "Unavailable. Refresh the skill catalogue.",
        requires_expansion = "This level requires the corresponding expansion.",
        set = "Learn / Set level", delete = "Forget skill", tools = "Tools", refresh = "Refresh catalogue",
        diagnostic = "Export diagnostics", waiting = "Waiting for a loaded save and skill catalogue",
        selection = "Selection", no_match = "No matching skills", read_only_suffix = " (read only)",
        bulk = "Learn in bulk", learn_job = "Learn all skills of selected vocation",
        learn_all = "Learn all vocations' skills", set_named = "Set skill: %s", delete_named = "Forget skill: %s",
        job_named = "Learn vocation skills: %s", refreshed = "Catalogue refreshed", exported = "Diagnostics exported",
        no_changes = "The requested state already matches. No changes needed.",
        done = "Updated %d skill records; unequipped %d slots.",
        failed = "Could not complete the operation. Export diagnostics or check the log.",
        restored = "Operation failed. The previous state was restored.",
        recovery_failed = "Recovery failed. Editing is locked.",
        editing_locked = "Editing is locked. Export diagnostics. If recovery failed, restore your save backup before saving.",
        journal_failed = "Changes completed, but the log could not be saved. Export diagnostics.",
        preview_changed = "State changed after the preview. Preview the operation again.",
        save_changed = "State changed while saving the snapshot. Preview the operation again.",
        pawn_missing = "Main Pawn is not available.", in_game_required = "Load a save before editing skills.",
        ui_error = "The interface could not be displayed. Export diagnostics or check the log.",
        language_not_saved = "Language changed, but the preference could not be saved.",
        skip_unavailable = "Skill metadata, valid levels or content availability could not be verified.",
        skip_unknown_level = "%s has an unverified saved level (%d). Export diagnostics.",
        skip_keep_higher = "%s already has level %d, above the available maximum %d. Kept unchanged.",
        skip_unlearned = "The native unlearned level could not be verified.",
    },
    zh = {
        title = "DD2 技能与职业管理", language = "语言", auto = "自动（跟随游戏）",
        page = "页面", skills_page = "技能", progress_page = "职业与 JP", both = "双方",
        progress_selection = "职业", qualification = "职业资格", unlocked = "已解锁", locked = "未解锁",
        vocation_edit = "编辑所选职业", jp_edit = "编辑 JP", jp_target = "目标 JP", vocation_unlock_all = "解锁全部职业",
        pending_confirmation = "当前保存尚未应用，请确认修改",
        not_applicable = "觉醒者专属", skip_pawn_job = "%s不能使用此职业",
        skip_unknown_job = "未能核验职业适用角色",
        vocation_rank_label = "职业等级", current_job = "当前职业", jp_balance = "JP 余额",
        vocation_unlock = "解锁职业", vocation_lock = "锁定职业", vocation_rank = "设置职业等级", jp = "设置 JP",
        progress_count = "职业 / JP 状态 %d 项", progress_done = "已修改 %d 项职业 / JP 状态",
        current_job_blocked = "此职业正在使用，请先在游戏中转职再锁定",
        basic_lock_blocked = "基础职业始终可用，无法锁定",
        mapping_unknown = "未能核验资格位图，暂不可锁定，请导出诊断",
        pawn_job_blocked = "主随从不能使用此职业", arisen_only = "此职业仅修改觉醒者",
        progress_unavailable = "职业数据暂不可修改，请导出诊断",
        jp_invalid = "请输入 0～2147483647 的整数", rank_invalid = "请选择有效职业等级",
        arisen = "觉醒者", pawn = "主随从", level = "等级 %d", learned = "已获取 · 等级 %d",
        not_learned = "未获取", not_loaded = "未载入", read_only = "只读",
        confirm_heading = "确认修改", state_count = "技能状态 %d 条",
        unequip_count = " · 自动卸下 %d 个槽位", skipped_count = " · 跳过 %d 项",
        actor = "角色", skill = "技能", change = "状态变化", unchanged = "保持原状",
        previous_page = "上一页", next_page = "下一页", unequip_list = "将卸下的技能槽",
        skipped_list = "跳过项", confirm = "确认修改", cancel = "放弃修改",
        current_state = "当前状态", state = "状态", job = "职业", search = "搜索",
        select_skill = "技能", settings = "设置技能", target_level = "目标等级",
        description = "技能说明", equipped = "已装备 · 变更时自动卸下",
        equipment_locations = "装备位置", slot = "槽位 %d", fallback_job = "职业 %d",
        unavailable_skill = "暂不可修改，请刷新技能目录", requires_expansion = "此等级需要拥有相应扩展内容",
        set = "学习 / 设置等级", delete = "删除技能", tools = "工具", refresh = "刷新目录",
        diagnostic = "导出诊断", waiting = "等待进入存档并载入技能目录",
        selection = "选择技能", no_match = "没有匹配技能", read_only_suffix = "（只读）",
        bulk = "批量学习", learn_job = "学习当前职业全部技能", learn_all = "学习全部职业技能",
        set_named = "设置技能：%s", delete_named = "删除技能：%s", job_named = "学习职业技能：%s",
        refreshed = "目录已刷新", exported = "诊断已导出", no_changes = "目标状态已一致，无需修改",
        done = "已修改 %d 条技能状态，自动卸下 %d 个槽位",
        failed = "操作未完成，请导出诊断或查看日志", restored = "操作失败，已恢复修改前状态",
        recovery_failed = "恢复失败，修改已暂停",
        editing_locked = "修改已锁定，请导出诊断。若恢复失败，请在保存前恢复完整存档备份。",
        journal_failed = "技能修改已完成，日志写入失败，请导出诊断",
        preview_changed = "预览后状态已变化，请重新预览", save_changed = "保存快照期间状态改变，请重新预览",
        pawn_missing = "主随从当前不可访问", in_game_required = "请进入存档后修改技能",
        ui_error = "界面未能显示，请导出诊断或查看日志", language_not_saved = "语言已切换，但偏好保存失败",
        skip_unavailable = "未能核验技能资料、有效等级或内容可用性",
        skip_unknown_level = "%s 已保存的等级 %d 无法核验，请导出诊断",
        skip_keep_higher = "%s 已有等级 %d，高于当前可用最高等级 %d，保持原状",
        skip_unlearned = "未能核验原生未获取等级",
    },
}

---Resolve the UI policy from reflected enum names. Unknown/non-Chinese means English.
---These misspellings are the actual via.Language names; never guess numeric IDs.
function M.resolve(mode, game_name)
    if mode == "zh" or mode == "en" then return mode end
    if game_name == "SimplelifiedChinese" or game_name == "TransitionalChinese" then return "zh" end
    return "en"
end

---Format a known presentation key, with English fallback for future missing translations.
function M.text(language, key, ...)
    local strings = M.strings[language] or M.strings.en
    local template = strings[key] or M.strings.en[key] or key
    return select("#", ...) > 0 and string.format(template, ...) or template
end

---Render structured notices so switching language never preserves old-language labels.
function M.notice(language, notice)
    if not notice then return "" end
    return M.text(language, notice.key, table.unpack(notice.args or {}))
end

---Render expected batch skips without exposing internal traces or untranslated reasons.
function M.skip(language, row)
    local data = row.reason_data or {}
    local role = M.text(language, data.role or "arisen")
    if row.reason_key == "pawn_job" then return M.text(language, "skip_pawn_job", role) end
    if row.reason_key == "unknown_job" then return M.text(language, "skip_unknown_job") end
    if row.reason_key == "unknown_level" then return M.text(language, "skip_unknown_level", role, data.level) end
    if row.reason_key == "keep_higher" then return M.text(language, "skip_keep_higher", role, data.level, data.maximum) end
    if row.reason_key == "unlearned" then return M.text(language, "skip_unlearned") end
    return M.text(language, "skip_unavailable")
end

return M
