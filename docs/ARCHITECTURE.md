# Architecture

## Modules

| Module | Responsibility |
| --- | --- |
| `DD2SkillStateManager.lua` | Single update/render callbacks, lifecycle, requests, preview/backup dispatch and persistent write lock |
| `access` | Reflected type/method/field contracts, actor access, collections, skill slots and minimal writes/recovery |
| `catalog` | Active-skill parameter discovery, vocation ownership, valid levels, content checks and localized text |
| `operations` | Individual/bulk skill preparation, allowed differences, automatic unequipping and rollback |
| `progress` | Vocation/JP requests, character scope, complete preflight, change whitelist and rollback |
| `progress_access` | Native vocation interfaces, qualification mapping, character/augment/equipment guards and exact experience recovery |
| `ui` | Portable-data ImGui rendering, page/selection state, responsive font/layout and request submission |
| `i18n` | English/Chinese presentation keys, formatting and structured notices; no game access |
| `diagnostics` | Read-only reflection reports, portable snapshot encoding, write/readback verification and logs |

## Lifetime and dispatch

Cross-frame catalogue/UI caches contain Lua values and text, not actor or component references. Reflection descriptors are cached by type and signature. Scene/save/actor changes invalidate portable state. Script reload clears module caches and deactivates old callbacks through the session flag.

UI buttons submit requests. The single `UpdateBehavior` pre-callback reacquires actors and handles both skill and progress transaction modules through `specification / prepare / backup / execute`. Native methods are resolved across inheritance by exact parameters, return type and staticness; ambiguity or mismatch disables the affected path.

## Transaction lifecycle

1. Build a request from the current catalogue and character rules.
2. Preflight all targets, recovery primitives and protected state; create a portable preview and fingerprint.
3. On confirmation, reacquire objects and compare the fresh state with the preview.
4. Save a complete pre-operation snapshot and verify its JSON readback.
5. Reacquire once more after disk I/O and check the fingerprint before writing.
6. Execute only planned changes, read back native/saved values and verify all out-of-scope data.
7. On failure, restore every target and verify recovery. Unverified recovery persists a global editing lock and exports diagnostics.

Snapshots include complete learning/equipment state and progress guards. Original references are pinned with REFramework-managed `add_ref` only for the final transaction; Lua GC owns their lifetime. No raw offsets or process-memory write APIs are used.

## Skill discovery and acquisition

Skills come from `CustomSkillInformationData` and `ExCustomSkillData`, grouped by job, skill ID and raw level. Discovery uses valid parameter and runtime enum records, not guessed ID ranges. Placeholder GUIDs, incompatible metadata and unverified ownership remain unavailable.

`EnabledCustomSkills` is a prepopulated table: record presence alone does not mean learned. Record `get_IsEnableProp`, context `isCustomSkillEnable` and `getCustomSkillLevel` are cross-checked. The native observations establish learned/unlearned grade semantics; acquired state and raw grade are stored separately, including sentinel rows.

Valid level choices also require reinforcement metadata and usable name/description GUIDs. Shared skills retain vocation-specific localized text. EX-marked variants are kept outside ordinary selectable levels; DLC weapon traits remain the native EX source. Expansion skills require verified content availability.

Learning/upgrading uses `setCustomSkillEnable`; downgrading edits the selected record's grade. Forgetting resets only that record to the verified native unlearned grade and preserves prepopulated rows. List removal/insertion exists solely for structural recovery.

## Equipment and protected state

Skill transactions enumerate all vocation palettes, including Warfarer references. Each slot is cross-checked against native equipment getters. Only references to actually changed skills enter the unequip plan; the job-None sentinel is never passed to a setter.

All planned slots are cleared with native `setSkill(job, None, slot)` before learning changes. An intermediate verification checks that only those slots changed and learning/protected data is intact. Final verification includes every learning row, relative ordering, grade/viewed flags, equipment and protected progress. Same-grade acquired edits preserve equipment; forgetting can also clear an abnormal equipped reference to an unlearned skill.

Rollback restores original learning records and uses native setters for slots. Guard-only fields are not silently rewritten to hide unexpected side effects. Skills and [vocation/JP edits](PROGRESS.md) have separate allowed-change rules; vocation edits compare raw skill/character guards and independently validate job data, without reusing a job-bearing immutable fingerprint.

## Presentation

The UI never accesses SDK objects. Current vocation information compares both characters; selection controls affect edit scope. Pending changes are shown at the top and confirmation area. Local font/table/disabled/color stacks are unwound on drawing errors. Labels use stable ImGui IDs across languages.

The CJK font loads once. Each draw uses the current REFramework default size; measured widths are invalidated by font-size or language changes. Narrow previews stack vertically and keep the concrete vocation name. See [localization](LOCALIZATION.md).
