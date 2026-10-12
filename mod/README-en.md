# DD2 Skill Controller 1.0

A REFramework Lua Mod for the PC Steam version of Dragon's Dogma 2. Manage active weapon skill acquisition and valid levels for the Arisen and Main Pawn, individually or in bulk. Skill discovery uses the game's own catalogue and text IDs.

Version 1.0 fixes valid vocation/JP writes being rolled back by a duplicated progress fingerprint. It adds bulk vocation unlocking, separate current/selected-vocation panels, green confirmation, red discard/locking, and a clear pending-changes message. It supports selectable progress targets, English/Chinese game text and a font that follows REFramework settings. Weapon EX remains game-managed.

## Install

Install REFramework separately. Close the game and back up the complete Steam `userdata/<Steam ID>/2054970/` directory before editing a save.

For manual installation, merge the ZIP's `reframework` folder into the game directory, beside `DD2.exe`. Keep the nine Lua files and the bundled CJK font/license together. No Python or extra Lua libraries are required by the Mod.

The ZIP also includes `modinfo.ini` for Fluffy Mod Manager. Select Dragon's Dogma 2, import the ZIP and enable it. The package layout is checked; a particular Fluffy version's deployment behavior has not been verified here.

## Vocations and JP

Choose **Vocations & JP** in the top **Page** selector. The read-only **Current state** panel always shows both characters’ current vocation, rank and JP. Under **Edit selected vocation**, select **Arisen**, **Main Pawn**, or **Both** and a vocation; the default target is Arisen. This section compares the selected vocation on both characters and contains the editing controls. **Edit JP** is a separate section using the same character target. Each action produces a preview and requires confirmation. Skill editing retains its original synchronization rules.

- **Unlock vocation** grants qualification only. First-change history and JP are retained; the game may charge its normal first-change fee. **Lock vocation** retains skills, equipment and experience. Change away from the vocation in game before locking it. Basic vocations remain available; unverified bitmap mappings disable locking.
- **Unlock all vocations** unlocks every eligible vocation for the selected targets, independently of the selected vocation. Already unlocked entries stay unchanged. Unsupported/unknown vocations are listed as skips; Arisen-only vocations are skipped for the Pawn. All actual changes use one transaction and preserve ranks, JP, skills and first-change history. Both requires both characters.
- **Set vocation rank** uses the game's maximum rank and native rank setter. Changing rank sets its corresponding cumulative vocation experience; setting the existing rank keeps experience progress. Character level, JP, skills and augments are protected.
- Arisen-only vocations cannot be edited for the Pawn. With Both selected, their vocation actions affect only the Arisen and show that scope in the preview.
- **Set JP** accepts an absolute whole-number balance from 0 to 2147483647. JP belongs to each character, across vocations. Both assigns the same balance to both characters; JP is not filtered by Arisen-only vocations.

Missing required targets cancel the whole action. Arisen-only editing does not require the Main Pawn. Selection/input changes cancel the preview. Snapshots are saved and read back before writing. Failed writes restore exact original experience and all affected targets; failed recovery locks all editing and requires a full save backup restore. If progress data is read only, export diagnostics for the actual layout/signature errors.

## Font size

Change the default font size in REFramework settings. The Mod's Chinese/English font follows it live, without a separate size setting or font reload. Columns and wrapping use measured glyphs; narrow previews stack vertically.

## Use and language

Load a save, open REFramework with Insert, and expand **DD2 Skill Controller** under **Script Generated UI**. Choose a vocation and skill, inspect the character states, select a level, then use **Learn / Set level** or **Forget skill**. Review the preview and click green **Confirm changes**. The highlighted pending message means nothing has been applied yet. Red **Discard changes** cancels the preview. Save normally in the game afterwards; the Mod does not trigger a save.

The top **Language** selector offers **Auto (game language)**, **中文**, and **English**. Auto reads the game's text language: either Chinese language maps to the Chinese UI; every other or unknown language maps to English. Chinese display uses Simplified Chinese. If the optional detector is unavailable, choose the language manually.

Vocation names, skill names and descriptions are requested explicitly in English or Chinese through the game's message API. The Mod does not change game language or voice settings. Unresolved game text falls back to the skill enum/ID; refresh the catalogue when needed.

Manual preferences are saved immediately to `reframework/data/DD2SkillStateManager/settings.json`. Switching language cancels the previous preview, clears the name search and rebuilds text caches. It does not change acquisition rules or make previously excluded levels available.

Skill descriptions, equipped locations, bulk actions and tools are collapsible. Bulk previews show ten character records per page. Name searches do not narrow the bulk operation's vocation/full-catalogue scope.

## Editing rules

- Only active weapon skills are edited. Basic attacks, core skills and passive augments are excluded.
- Ordinary vocation skills synchronize the Arisen and Main Pawn. If either required character is unavailable, the entire operation is cancelled. Arisen-only vocation skills affect only the Arisen.
- Explicit learning can bypass vocation rank, JP purchase and master-skill acquisition conditions. It does not grant vocations, spend JP, advance quests or unlock unowned expansion content.
- Each skill uses its own verified normal levels. Single-level skills keep one level. EX is supplied by DLC weapon affixes and stays entirely game-managed; the Mod does not grant EX or edit weapons/affixes.
- Presence in the preallocated table does not mean acquired. Native record/context getters verify acquisition and level. Forgetting preserves the table and resets only the selected record to an observed, verified unlearned level.
- Before forgetting or an actual level change, automatically unequip all affected references on the target characters, including inactive vocation palettes and Warfarer references. The preview lists the affected slots. Changed skills remain unequipped afterwards.
- An already learned, identical level is a no-op and retains equipment. Explicit forgetting also clears stale equipment references to an already unlearned skill.
- Bulk learning selects each skill's highest available level. If a character already has a higher saved level, the synchronized skill is skipped rather than downgraded. Use a single explicit operation to lower its level.
- Buttons act once. The Mod does not continuously overwrite normal learning or equipment behavior.

## Recovery, diagnostics and uninstall

Before every actual transaction, write and read back complete learning, equipment and protected-progress snapshots. Unequipping and learning are one transaction. Any failure attempts to restore all target characters' original records and slots, then verifies the complete state. Failed recovery locks further editing; do not save that failed state, and restore a complete save backup.

Snapshots (`before_*.json`), result logs (`operation_*.json`) and exported diagnostics are in `reframework/data/DD2SkillStateManager/`. Use **Tools → Export diagnostics** for interface, native-contract or language issues. Internal errors remain in logs/diagnostics rather than the interface.

JSON snapshots are not complete game saves and have no automatic import function. Close the game and restore the original account's complete `2054970` backup when a full recovery is needed; account for Steam Cloud synchronization. Remove `writer-lock.json` only after restoring and checking the save.

To uninstall, close the game and remove only `DD2SkillStateManager.lua`, its module folder and the two `DD2SkillStateManager-CJK` font/license files. Fluffy users can disable the Mod through the manager. Saved learning changes remain after uninstalling; backups/diagnostics can be retained separately.

Original code is MIT licensed. The bundled Noto Sans CJK SC font is distributed with its SIL OFL 1.1 license. See `THIRD_PARTY_NOTICES.md` and the included static-check report.

## 1.0 validation status

The latest 0.4.0 export confirms both actors’ native progress interfaces, complete character/augment/equipment protection and exact experience recovery. Operation logs identify the erroneous rollback; 1.0 removes only the duplicate job-bearing fingerprint and keeps raw protected values and the progress whitelist. Ordinary skill editing has successful game logs and user confirmation.

Syntax, API references, translations, mutation boundaries and ZIP contents are statically checked. Fixed vocation/JP writes, bulk unlocking and the revised UI still need in-game verification. No automated tests or game simulations were run.
