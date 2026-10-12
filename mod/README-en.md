# DD2 Skill Controller — User guide

A REFramework Lua Mod for Dragon's Dogma 2 on PC Steam. Manage active weapon skills, vocation qualification, vocation rank and JP for the Arisen and Main Pawn.

## Requirements and installation

Install [REFramework](https://github.com/praydog/REFramework) separately. Close the game and back up the complete Steam `userdata/<Steam ID>/2054970/` directory before editing a save.

**Manual installation:** merge the installation ZIP's `reframework` folder into the game directory beside `DD2.exe`. Keep this layout:

```text
reframework/
  autorun/
    DD2SkillStateManager.lua
    DD2SkillStateManager/
      access.lua
      catalog.lua
      diagnostics.lua
      i18n.lua
      operations.lua
      progress.lua
      progress_access.lua
      ui.lua
  fonts/
    DD2SkillStateManager-CJK.otf
    DD2SkillStateManager-CJK-LICENSE.txt
```

**Fluffy Mod Manager:** select Dragon's Dogma 2, import the installation ZIP and enable it. The ZIP contains `modinfo.ini`. Use the installation ZIP rather than the source ZIP; the package structure is checked, but manager-specific installation behavior needs manual verification.

No Python or additional Lua libraries are needed at runtime.

## Skills

1. Load a save, press Insert and open **Script Generated UI → DD2 Skill Controller**.
2. Select **Skills**, choose a vocation and select a skill. Search by name or ID if needed.
3. Inspect the current states and choose a valid level.
4. Click **Learn / Set level** or **Forget skill**, review the preview, then click green **Confirm changes**.
5. Equip the skill again if it was automatically unequipped, and save normally in game.

Ordinary vocation skills synchronize the Arisen and Main Pawn. Arisen-only vocations affect only the Arisen. Missing a required character cancels the whole action. Only levels verified for that particular skill are offered; single-level skills have one acquired level. Acquisition and raw level are tracked separately.

An actual level change or deletion automatically clears all affected skill slots, including saved palettes for other vocations and Warfarer references. The preview lists them. Unchanged acquired levels keep equipment; cleared slots are not automatically re-equipped.

**Learn in bulk** offers the selected vocation or all vocations. Each skill uses its own highest eligible level. Search text does not narrow the batch. Existing higher saved levels are kept by skipping that synchronized skill; use an individual edit for an intentional downgrade. Unverified or unavailable content is listed as a skip.

## Vocations and JP

Select **Vocations & JP**. **Current state** always shows both characters' current vocation, rank and JP as read-only information.

Under **Edit selected vocation**, select **Arisen**, **Main Pawn** or **Both**, then a vocation. The default target is Arisen. The section compares the selected vocation on both characters and contains its editing controls.

| Action | Behavior |
| --- | --- |
| Unlock vocation | Grants qualification; preserves first-change history, rank, JP, skills and equipment. The game's normal first-change fee still applies. |
| Lock vocation | Removes qualification but retains progress and saved equipment. Change away from the vocation first. Basic vocations cannot be locked. |
| Set vocation rank | Uses the game's valid rank range and corresponding cumulative vocation experience. Setting the existing rank keeps experience progress. Does not learn skills or change character level or JP. |
| Unlock all vocations | Unlocks all eligible vocations for the selected character scope, independently of the vocation selector. Already unlocked entries stay unchanged. |
| Set JP | Sets an absolute whole-number balance from 0 to 2147483647 under **Edit JP**. Both assigns the same value to both characters. |

Arisen-only vocation actions cannot target the Pawn; with Both selected, they affect only the Arisen. Bulk unlocking lists those Pawn entries as skips. JP always follows the character selector. Any missing required target cancels the entire transaction. Unverified qualification mapping disables locking.

## Confirmation, language and font

Every editing button creates a preview. **These changes have not been applied** means the edit is pending; click green **Confirm changes** to apply or red **Discard changes** to cancel. Changing character, vocation, level, JP input, page or language cancels the old preview.

**Language** offers Auto, 中文 and English. Auto reads game text language: Chinese uses the Chinese UI; all other or unknown languages use English. Manual preferences are saved in `reframework/data/DD2SkillStateManager/settings.json`. Vocation/skill names and descriptions are requested from the game in the selected language. The Mod does not change game language or voice settings.

Change font size in REFramework settings. The bundled font follows it live, with measured wrapping and a compact preview layout for narrow panels. No separate Mod font-size setting is required.

## Scope and persistence

The Mod edits active weapon skills and the selected vocation/JP fields. It does not edit core skills, augments, character level, quests or content ownership. Learning an eligible selected skill bypasses its rank, JP purchase and mastery conditions; rank editing does not automatically learn skills. Unowned expansion content is not unlocked.

**Weapon EX skills remain provided by DLC weapon traits.** EX variants are excluded from normal level selection and bulk grants; weapons and traits retain their native behavior.

Actions run once when confirmed and do not continuously override game progression. Changes persist through normal game saving. Uninstalling does not undo saved edits.

## Troubleshooting and recovery

If the catalogue is not ready, open the game's weapon-skill menu once, then use **Tools → Refresh catalogue**. Unresolved names fall back to enum names or IDs. For unavailable characters, read-only data, language issues or failed operations, use **Tools → Export diagnostics**.

Files in `reframework/data/DD2SkillStateManager/`:

| File | Purpose |
| --- | --- |
| `settings.json` | Language preference |
| `before_*.json` | Pre-operation snapshots |
| `operation_*.json` | Operation results |
| `diagnostic_*.json` | Read-only runtime diagnostics |
| `writer-lock.json` | Persistent lock after unverified recovery |

Before writing, the Mod saves and reads back a snapshot. Failed transactions attempt to restore every target and verify the complete state. If recovery fails, editing is locked: avoid saving that state and restore your full save backup.

JSON snapshots are not complete game saves and cannot be imported. For full recovery, close the game and restore the original account's complete `2054970` directory, taking Steam Cloud synchronization into account. Remove `writer-lock.json` only after restoring and checking the save.

Before sharing diagnostics, review them for private file paths or character data. Report the game/REFramework versions, action, target, expected result and actual result. Never publish your complete save backup.

## Uninstall

Close the game. Remove only `DD2SkillStateManager.lua`, its module directory and the two bundled `DD2SkillStateManager-CJK` font/license files, or disable the Mod through Fluffy. Preferences and diagnostics can be retained separately or removed from this Mod's data folder. Other Mods are unaffected by removing only these files.

## Compatibility and license

Reference environment: game `4.0.0.0`, Steam build `25290080`, REFramework `d1461375aee4ec3f313170f8eaad12064eb542d9`, TDB 83. Reflection prechecks disable editing when required contracts cannot be verified.

Core skill editing and automatic unequipping have manual validation. Runtime vocation/JP structures are verified; current vocation/JP edits, bulk unlocking and the revised UI still need manual confirmation. Static reports describe syntax, interfaces and packaging, not proof of in-game behavior.

Original code is MIT licensed. The bundled Noto Sans CJK SC font uses SIL OFL 1.1. See `THIRD_PARTY_NOTICES.md` and the included licenses.
