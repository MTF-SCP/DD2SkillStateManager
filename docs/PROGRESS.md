# Vocation and JP design

## Character rules

Progress editing supports Arisen, Main Pawn and Both, defaulting to Arisen. Required targets must all be available before any write. Known ordinary vocations (`Job01`–`Job06`) can target both characters; Arisen-only vocations (`Job07`–`Job10`) reject Pawn-only requests and reduce a Both single-vocation request to the Arisen. Unknown ownership remains read-only.

JP follows the character selector independently of vocation selection. Current-state and selected-vocation views compare both characters even when only one is an edit target.

## Native contracts

| Field | Write path | Readback |
| --- | --- | --- |
| Qualification unlock | `setJobQualified(JobEnum)` | `isJobQualified(JobEnum)` and saved bitmap |
| Qualification lock | Clear only the verified target bit | Native qualification query and exact bitmap difference |
| Vocation rank | `setJobExpWithJobRank(JobEnum, UInt32)` | `calcJobRank`, `getJobExp` and `getMaxJobRank` |
| JP | `set_ConsumableExpProp(Int32)` | Native getter and saved `ConsumableExp` field |

Qualification changes preserve first-change history, viewed flags, experience, JP, skills and saved equipment. Basic vocations cannot be locked. Locking the active vocation is rejected; the player must change vocation in game first.

Qualification bit candidates are checked against accessible characters' native queries, excluding Pawn-only unsupported-vocation evidence. Locking requires a unique mapping. Unlocking uses the native setter; verification checks preserved original bits, expected added-bit count, individual native queries and the exact expected mask whenever mapping is known.

Rank choices use the game's reported maximum, intersected across selected targets. Values above 128 are rejected as corrupt interface data; this sanity bound is not the game's maximum rank. An existing-rank request is a no-op preserving within-rank experience. A changed rank uses the native cumulative-experience setter, without awarding JP, character experience, skills or augments.

JP is one consumable balance per character, not a balance per vocation. Accepted values are absolute integers from 0 to 2147483647. Rejection, clamping or saved/native disagreement fails the transaction and restores the original balance.

## Bulk unlocking

`vocation_unlock_all` creates character/vocation items from the same catalogue. Unknown ownership and Arisen-only vocations for the Pawn become explicit preview skips. The selected vocation does not narrow the action. Already qualified entries are shown unchanged and never call a setter.

Each character is snapshotted once; every item and all recovery contracts are validated before the first write. Only missing eligible qualifications call `setJobQualified`. All actual changes are one transaction. Final verification requires the exact allowed qualification differences while experience, ranks, JP, history, viewed flags, skills and equipment remain unchanged. Any failure restores every target.

## Protection and exact recovery

`progress` implements the shared `specification / prepare / backup / execute` contract. Per-character changes contain role, field, optional job ID, before/after values and a write flag. Portable previews contain no game objects and expire when inputs, page, language or relevant game state changes.

Preflight saves all vocation fields/experience, active and core skills, skill slots, character level/experience/growth, augment acquisition/equipment and saved vocation armor/weapon configurations. Progress operations allow only the requested qualification bit(s), selected job experience or JP to differ. Other raw values and native queries must remain equal.

Job data has its own whitelist. Skill/character protection excludes both the job subtree and its derived job-bearing fingerprint, while retaining the remaining raw protected values. A mismatch records the protected field path for diagnosis.

Cumulative experience is a `System.Int32[]`. Length, boxed element types, current job index and per-job native experience are cross-checked. Normal editing uses native setters. The final transaction pins the original context/array, learning records and independent boxed experience copies.

Rollback restores original cumulative experience rather than using a rank setter that loses within-rank progress. Array assignment uses REFramework's managed, type-checked `System.Array.SetValue(Object, Int32)` path or checked array `Set(Int32, Int32)` fallback. A valid signature and readback are required; raw offsets and fabricated objects are not used.

Rollback also restores original vocation scalars, learning and skill slots. Unexpected character/augment/saved-gear changes are guard failures. If complete recovery cannot be proven, all editing is locked and diagnostics are exported; partial recovery is never reported as success.

See [architecture](ARCHITECTURE.md) for shared dispatch and [validation](RUNTIME_VALIDATION.md) for manual acceptance cases.
