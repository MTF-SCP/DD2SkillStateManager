-- SPDX-License-Identifier: MIT
local access = require("DD2SkillStateManager/access")
local M = {}

local function sorted_keys(set)
    local list = {}
    for key in pairs(set) do list[#list + 1] = key end
    table.sort(list)
    return list
end

local function optional_bool(param, name)
    local value = access.optional_get(param, name)
    if value == nil then return nil end
    return access.boolean(value)
end

-- Shared Mage/Sorcerer skills have job-specific text GUIDs but one saved ID/grade.
-- Compare duplicates within the SAME job; prefer the origin job for canonical
-- metadata and keep the other job's localization as an explicit alternative.
local function merge_variant(skill, variants, candidate, origin_job)
    local existing = variants[candidate.level]
    if not existing then candidate.alternates = {}; variants[candidate.level] = candidate; return end
    local same = existing.job == candidate.job and existing or nil
    for _, other in ipairs(existing.alternates) do if other.job == candidate.job then same = other end end
    if same then
        if same.name_guid ~= candidate.name_guid or same.description_guid ~= candidate.description_guid
            or same.reinforceable ~= candidate.reinforceable then
            skill.valid = false
            skill.reasons["同一职业、技能类别及等级的参数不一致，暂不可修改"] = true
        end
        same.expansion = same.expansion and candidate.expansion
        if candidate.has_name and not same.has_name then same.name, same.has_name = candidate.name, true end
        if same.description == "" then same.description = candidate.description end
        if same.validation_description == "" then same.validation_description = candidate.validation_description end
    elseif candidate.job == origin_job then
        candidate.alternates = existing.alternates
        existing.alternates = nil -- Never retain recursive catalogue values.
        candidate.alternates[#candidate.alternates + 1] = existing
        variants[candidate.level] = candidate
    else
        existing.alternates[#existing.alternates + 1] = candidate
    end
end

---Discover only weapon custom skills from game-owned parameter tables, including new IDs.
---@return table
function M.build(language)
    local result = {by_id = {}, jobs = {}, job_order = {}, warnings = {}, source_count = 0, language = language or "en"}
    access.records(access.actor("arisen")) -- Populate native grade semantics through read-only getters.
    local pawn_ok, pawn_error = pcall(function() access.records(access.actor("pawn")) end)
    if not pawn_ok then result.warnings[#result.warnings + 1] = "主随从等级语义采样不可用：" .. tostring(pawn_error) end
    result.learning_model = access.learning_model()
    local job_enum = access.enum("app.Character.JobEnum")
    local skill_enum = access.enum("app.HumanCustomSkillID")
    local level_enum = access.enum("app.HumanCustomSkillLevelNo")
    result.expansion_owned, result.ownership_source = access.expansion_owned()
    for name, id in pairs(job_enum.values) do
        local number = tonumber(name:match("^Job(%d%d)$"))
        if number and id > 0 then
            result.jobs[id] = {id = id, number = number, name = access.job_name(id, result.language), skills = {}}
            result.job_order[#result.job_order + 1] = id
        end
    end
    table.sort(result.job_order)
    assert(#result.job_order > 0, "职业目录未载入")
    local seen_data = {}
    for _, behavior in ipairs(access.gui_behaviors()) do
        for _, source in ipairs({"CustomSkillInformationData", "ExCustomSkillData"}) do
            local data = access.optional_get(behavior, source)
            if data and not seen_data[access.address(data)] then
                seen_data[access.address(data)] = true
                result.source_count = result.source_count + 1
                local sets = assert(access.get(data, "_Params"), "技能参数集未载入")
                for i = 0, access.count(sets) - 1 do
                    local group = access.item(sets, i)
                    if group then
                        local job = access.integer(access.get(group, "_Job"))
                        local params = assert(access.get(group, "_Params"))
                        for j = 0, access.count(params) - 1 do
                            local param = access.item(params, j)
                            if param then
                                local id = access.integer(access.get(param, "_SkillID"))
                                local level = access.integer(access.get(param, "_Level"))
                                local name_guid = access.get(param, "_SkillName")
                                local guid_text = access.guid_text(name_guid)
                                local placeholder = guid_text == "00000000-0000-0000-0000-000000000000"
                                if id > 0 and result.jobs[job] and level_enum.names[level] and not placeholder then
                                    local skill = result.by_id[id]
                                    if not skill then
                                        skill = {id = id, key = skill_enum.names[id] or ("Skill " .. id),
                                            jobs = {}, variants = {}, ex_variants = {},
                                            valid = true, reasons = {}, excluded_levels = {}}
                                        result.by_id[id] = skill
                                    end
                                    skill.jobs[job] = true
                                    -- A future non-enum ID can be displayed, but not written until
                                    -- its runtime method contract is known to accept that value.
                                    if not skill_enum.names[id] then
                                        skill.valid = false
                                        skill.reasons["技能 ID 尚未出现在当前游戏枚举中"] = true
                                    end
                                    if not guid_text then
                                        skill.valid = false
                                        skill.reasons["无法核验技能文本标识是否为占位数据"] = true
                                    end
                                    local name = access.message(name_guid, result.language)
                                    local description_id = access.get(param, "_SkillText")
                                    local description = access.message(description_id, result.language)
                                    -- Translation is presentation-only: a language dropdown
                                    -- must not make a previously excluded grade grantable.
                                    -- Keep the existing game-language validation independent
                                    -- from explicitly requested English/Chinese display text.
                                    local validation_description = access.message(description_id)
                                    local marked_ex = optional_bool(param, "_IsExSkill")
                                    if marked_ex == nil then
                                        skill.valid = false
                                        skill.reasons["扩展技能标记字段不可读取"] = true
                                    end
                                    -- The live Ex table contains BOTH new normal skills and
                                    -- EX enhancements. An EX row reuses the normal ID/Lv1,
                                    -- but is not the same saved Level. EX is supplied by DLC
                                    -- weapon affixes, so this editor never grants it or changes
                                    -- its source. Retain these rows only as reference metadata.
                                    local variants = marked_ex == true and skill.ex_variants or skill.variants
                                    local expansion = source == "ExCustomSkillData" or marked_ex == true
                                    local description_guid = access.guid_text(access.get(param, "_SkillText"))
                                    local reinforceable = optional_bool(param, "_Reinforceability")
                                    local candidate = {job = job, level = level, name = name or skill.key,
                                            description = description or "", expansion = expansion,
                                            validation_description = validation_description or "",
                                            ex_enhancement = marked_ex == true,
                                            reinforceable = reinforceable,
                                            raw_rank = access.integer(access.get(param, "_UnlockRank")),
                                            raw_cost = access.integer(access.get(param, "_Cost")),
                                            name_guid = guid_text, description_guid = description_guid,
                                            has_name = name ~= nil}
                                    local origin_number = tonumber(skill.key:match("^Job(%d%d)_"))
                                    local origin_job
                                    for job_id, info in pairs(result.jobs) do
                                        if info.number == origin_number then origin_job = job_id end
                                    end
                                    merge_variant(skill, variants, candidate, origin_job)
                                elseif id > 0 and not placeholder then
                                    result.warnings[#result.warnings + 1] =
                                        "忽略无法核验的参数: job=" .. job .. ", skill=" .. id .. ", level=" .. level
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    assert(result.source_count > 0, "主动技能参数表尚未载入；打开一次职业公会菜单后刷新")
    result.order = sorted_keys(result.by_id)
    assert(#result.order > 0, "参数表中没有有效的武器主动技能")
    for _, id in ipairs(result.order) do
        local skill = result.by_id[id]
        local raw_levels, learned_levels = sorted_keys(skill.variants), {}
        local first
        for _, level in ipairs(raw_levels) do
            if level ~= result.learning_model.unlearned_level then
                local variant = skill.variants[level]
                local reason
                if first then
                    -- GUI tables also retain dummy Lv2 rows for single-level masters.
                    -- Do not promote those merely because the enum/row exists. The
                    -- lower-level upgrade flag and real text metadata must agree.
                    if first.reinforceable ~= true then reason = "前一级参数未确认可强化"
                    elseif variant.name_guid == first.name_guid and variant.description_guid == first.description_guid then
                        reason = "与低等级使用相同名称及说明，不作为独立升级"
                    elseif not variant.description_guid or variant.description_guid == "00000000-0000-0000-0000-000000000000" then
                        reason = "缺少有效技能说明，疑似占位升级"
                    elseif variant.validation_description == "" then
                        reason = "升级说明尚不可解析，暂不提供此等级；可刷新重试"
                    end
                end
                if reason then skill.excluded_levels[#skill.excluded_levels + 1] = {level = level, reason = reason}
                else learned_levels[#learned_levels + 1], first = level, variant end
            end
        end
        skill.levels, skill.selectable = learned_levels, {}
        for _, level in ipairs(learned_levels) do skill.selectable[level] = true end
        if #learned_levels == 0 then
            skill.valid = false
            skill.reasons["缺少可核验的普通技能等级；武器 EX 强化不属于编辑范围"] = true
        end
        local owner_number = tonumber(skill.key:match("^Job(%d%d)_"))
        local owner_job
        for job in pairs(skill.jobs) do
            if result.jobs[job].number == owner_number then owner_job = job end
        end
        -- Origin metadata, rather than the selected display filter, determines the targets.
        -- Shared skills may also occur in Sorcerer or Warfarer tables.
        if not owner_job then
            skill.valid = false
            skill.reasons["技能所属职业与参数表无法交叉核验"] = true
        elseif owner_number >= 1 and owner_number <= 6 then
            skill.target = "both"
        elseif owner_number >= 7 and owner_number <= 10 then
            skill.target = "arisen"
        else
            skill.valid = false
            skill.reasons["未知职业的随从适用规则"] = true
        end
        skill.owner_job = owner_job
        local display = skill.variants[skill.levels[1]] or skill.ex_variants[sorted_keys(skill.ex_variants)[1]]
        skill.name = display and display.name or skill.key
        skill.reason = table.concat(sorted_keys(skill.reasons), "；")
        for job in pairs(skill.jobs) do
            result.jobs[job].skills[#result.jobs[job].skills + 1] = id
        end
    end
    for _, job in pairs(result.jobs) do table.sort(job.skills) end
    -- The stamp excludes translated text: changing UI language cannot change operation scope.
    local stamp = {}
    for _, id in ipairs(result.order) do
        local skill = result.by_id[id]
        local variants = {}
        for _, level in ipairs(skill.levels) do
            local variant = skill.variants[level]
            variants[#variants + 1] = tostring(level) .. ":" .. tostring(variant.expansion)
                .. ":" .. tostring(variant.reinforceable) .. ":" .. tostring(variant.name_guid)
                .. ":" .. tostring(variant.description_guid)
        end
        stamp[#stamp + 1] = id .. "/" .. tostring(skill.target) .. "/" .. tostring(skill.valid)
            .. "/" .. table.concat(sorted_keys(skill.jobs), ",") .. "/" .. table.concat(variants, ",")
    end
    result.stamp = table.concat(stamp, "|") .. "/owned=" .. tostring(result.expansion_owned)
    for _, row in ipairs(result.learning_model.observations) do
        result.stamp = result.stamp .. "/grade=" .. row.level .. ":" .. tostring(row.learned)
    end
    return result
end

function M.grantable(catalog, skill, level)
    if not skill.valid then return false, skill.reason end
    if not catalog.learning_model.valid then return false, "原生等级获取语义冲突，停止修改" end
    if not catalog.learning_model.enabled[level] then return false, "此等级未被原生属性确认是已获取等级；请导出诊断" end
    local variant = skill.variants[level]
    if not variant or not skill.selectable[level] then return false, "该技能没有可用的所选等级" end
    if variant.expansion and catalog.expansion_owned ~= true then
        return false, catalog.expansion_owned == false and "未拥有该扩展内容" or "无法核验扩展内容所有权"
    end
    return true
end

---Select the highest individually valid grade, never the highest global enum value.
function M.highest(catalog, skill)
    for i = #skill.levels, 1, -1 do
        local level = skill.levels[i]
        if M.grantable(catalog, skill, level) then return level end
    end
    return nil
end

function M.export(catalog)
    if not catalog then return nil end
    local out = {stamp = catalog.stamp, language = catalog.language, expansion_owned = catalog.expansion_owned,
        ownership_source = catalog.ownership_source, warnings = catalog.warnings,
        learning_model = {valid = catalog.learning_model.valid,
            unlearned_level = catalog.learning_model.unlearned_level,
            observations = catalog.learning_model.observations},
        jobs = {}, skills = {}}
    for _, id in ipairs(catalog.job_order) do
        local job = catalog.jobs[id]
        out.jobs[#out.jobs + 1] = {id = id, name = job.name, skills = job.skills}
    end
    for _, id in ipairs(catalog.order) do
        local skill = catalog.by_id[id]
        local variants, ex_variants = {}, {}
        for _, level in ipairs(skill.levels) do variants[#variants + 1] = skill.variants[level] end
        for _, level in ipairs(sorted_keys(skill.ex_variants)) do ex_variants[#ex_variants + 1] = skill.ex_variants[level] end
        out.skills[#out.skills + 1] = {id = id, key = skill.key, name = skill.name,
            jobs = sorted_keys(skill.jobs), owner_job = skill.owner_job, target = skill.target,
            valid = skill.valid, reason = skill.reason, variants = variants,
            ex_variants = ex_variants, excluded_levels = skill.excluded_levels}
    end
    return out
end

return M
