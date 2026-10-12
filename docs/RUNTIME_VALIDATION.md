# Validation

Static results and in-game behavior are recorded separately. A passing build proves the inspected syntax, references and archive contents; it does not prove every native game operation or save-persistence scenario.

## Reference environment

| Component | Reference |
| --- | --- |
| Platform | PC Steam, Dragon's Dogma 2 |
| Game version | `4.0.0.0` |
| Steam build | `25290080` |
| REFramework | `d1461375aee4ec3f313170f8eaad12064eb542d9` |
| TDB | 83 |

The Mod resolves exact runtime signatures and disables unsupported editing paths instead of guessing offsets. Other builds need their own runtime confirmation.

## Evidence and current limits

| Area | Evidence / status |
| --- | --- |
| Lua, module/API references, localization and write boundaries | Checked by the static build gate; generated reports hold exact results. |
| Installation/source archives | Entry tree, CRC, duplicate names and SHA-256 checked by packaging. |
| Core skill editing | Confirmed through manual play and successful operation logs. |
| Automatic unequipping | A deletion with automatic slot clearing and synchronized re-learning is confirmed. Other palette/reference combinations still need explicit coverage. |
| Acquisition semantics and native skill levels | Cross-checked against exported per-record native/saved state. |
| Vocation/JP and recovery structures | Both actors' exported native capabilities, qualification mapping, cumulative experience and protection collections are readable and consistent. |
| Current vocation qualification/rank/JP writes and bulk unlock | Manual acceptance is still pending; structure/signature evidence alone is not a successful-write result. |
| Language, font and revised layout | Static keys/bindings checked; rendering, live scaling and preference persistence need manual confirmation. |
| Recovery edge cases and save persistence | Not fully covered; no forced failure is claimed. |
| Fluffy Mod Manager | Installation layout checked; manager-specific deployment requires manual confirmation. |

The build performs no automated gameplay tests, game emulation or Mod execution. Private raw exports and backups remain local and are excluded from Git/release packages.

## Manual acceptance checklist

Back up the complete save before write verification. Review each preview and explicitly confirm it. For reversible checks, record original values and restore them through the normal UI afterwards.

| Case | Expected result |
| --- | --- |
| Learn/forget/set a selected ordinary skill | Both required characters match the request; unrelated learning/slots do not change. |
| Single-level/master/expansion skills | Only verified ordinary grades are offered; ownership rules hold; weapon EX remains game-managed. |
| Equipped skill change | Only previewed references clear, including other vocation palettes/Warfarer; unchanged grades retain equipment. |
| Bulk skill learning | Each skill uses its own highest eligible grade; higher saved grades and unavailable content are skipped as specified. |
| Arisen/Pawn/Both progress targets | Only the actual previewed targets change; missing required targets cancel the whole operation. |
| Arisen-only vocation | Pawn-only editing is disabled; Both single-vocation edits affect only the Arisen. |
| Qualification and all-vocation unlock | Only eligible qualification bits change; ranks, JP, history, skills and equipment remain intact. |
| Locking | Active/basic vocations cannot be locked; locked vocation progress and saved equipment are retained. |
| Rank increase/decrease/same rank | Native rank is correct; same-rank experience progress is preserved; no character-level, JP or skill side effects. |
| JP integer/range/normal spending | Valid absolute balances read back exactly; invalid inputs do not write; normal game consumption remains functional. |
| Preview expiry and discard | Changed selection/state cancels old confirmation; discarded edits produce no write. |
| English/Chinese, large font, narrow panel | Controls remain legible; game text matches the chosen language; font tracks REFramework and stacks do not leak. |
| Normal save and restart | Accepted edits persist through the game's ordinary saving mechanism. |

## Diagnostic workflow

Load a save, open the relevant page and choose **Tools → Export diagnostics**. Relevant files live under game `reframework/data/DD2SkillStateManager/`:

- `diagnostic_*.json`: read-only signatures, catalogue, actor state, qualification mapping, progress/recovery contracts and font information.
- `before_*.json`: complete pre-operation snapshot, not an importable game save.
- `operation_*.json`: requested scope, planned changes, result and recovery status.

Compare the recorded before/after values with the native/saved field checks; do not infer success from a preview or interface availability. If an operation fails, retain its result and matching snapshot. Review private data before sharing excerpts, and include the game/REFramework/Mod versions and exact action. Never publish full save backups.

If recovery is unverified, restore a complete save backup before saving again. See the [English user guide](../mod/README-en.md) or [中文使用指南](../mod/README-zh-CN.md) for recovery and removal of the persistent editing lock.
