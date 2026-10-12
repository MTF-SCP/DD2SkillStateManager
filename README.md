# DD2 Skill Controller

[简体中文](README-zh-CN.md) · [User guide](mod/README-en.md)

A [REFramework](https://github.com/praydog/REFramework) Lua Mod for **Dragon's Dogma 2 on PC Steam**. Manage active weapon skills, vocation qualification, vocation rank and JP for the Arisen and Main Pawn through an English/Chinese ImGui interface.

## Features

- **Precise skill editing:** learn, forget or set an individual skill's valid level. Discover skills from the game, filter by vocation and search by name or ID.
- **Bulk learning:** learn all skills of the selected vocation or all vocations, using each skill's highest eligible level. Search filters do not narrow bulk actions.
- **Automatic unequipping:** clear affected skill slots before forgetting or changing an equipped skill, including saved vocation palettes and Warfarer references.
- **Vocations and JP:** unlock or lock vocations, set vocation rank, unlock all eligible vocations, and set JP for the Arisen, Main Pawn or both.
- **Review before applying:** preview exact changes, confirm with the green button or discard with the red button. Transactions save snapshots, verify results and attempt full rollback on failure.
- **Native localization:** automatically use Chinese for Chinese game text settings and English for other languages. Manual selection is saved; font size follows REFramework live.

Passive abilities, core skills, character level, quests and content ownership are outside the editing scope. Weapon EX skills remain governed by the game's DLC weapon traits.

## Installation

Requires REFramework. No additional runtime libraries are needed.

1. Close the game and back up the complete Steam `userdata/<Steam ID>/2054970/` directory.
2. Merge the installation ZIP's `reframework` folder into the game directory beside `DD2.exe`.
3. Alternatively, import the installation ZIP into Fluffy Mod Manager with Dragon's Dogma 2 selected, then enable it.
4. Load a save, press Insert and open **Script Generated UI → DD2 Skill Controller**.

Use the installation ZIP for playing; the source ZIP is for development. Keep the bundled Chinese font and its license with the Lua scripts. See the [user guide](mod/README-en.md) for recovery and uninstall instructions.

## Usage

**Skills:** select a vocation and skill, choose a level, then click **Learn / Set level** or **Forget skill**. Ordinary vocation skills synchronize both characters; Arisen-only vocations affect only the Arisen. An unavailable required character cancels the action. Changed skills are unequipped and must be equipped again in game.

**Vocations & JP:** the current-state panel always shows both characters. Choose the edit target and vocation in the editing section. Vocation rank, qualification and JP are separate operations. **Unlock all vocations** uses the character target and skips vocations the Pawn cannot use.

Every editing button creates a preview. Read it and click **Confirm changes** to apply; a pending message means the edit has not been applied yet. Changing the selection or choosing **Discard changes** cancels the preview. Save normally in game afterwards; the Mod does not trigger saves.

## Compatibility and validation

The reference environment is game `4.0.0.0`, Steam build `25290080`, REFramework commit `d1461375aee4ec3f313170f8eaad12064eb542d9`, TDB 83. Reflection checks disable unsupported editing paths when contracts cannot be verified.

Core skill editing and automatic unequipping have manual validation. Vocation/JP structures are verified against exported runtime data; current vocation/JP writes, bulk unlocking and the revised interface still need in-game confirmation. Static checks do not prove game behavior. See the [validation checklist](docs/RUNTIME_VALIDATION.md).

## Development

With Python 3.12, run from the repository root:

```powershell
python -m pip install --target .tools/python -r tools/requirements-static.txt
python tools/fetch_references.py
python tools/build.py
```

The build performs static checks and generates installation/source ZIPs plus `SHA256SUMS.txt` in `dist/`. It does not launch the game, execute the Mod or install it. See [development](docs/DEVELOPMENT.md) and [contributing](CONTRIBUTING.md).

| Directory | Contents |
| --- | --- |
| `mod/` | Installable Lua modules, licensed font and bilingual user guides |
| `docs/` | Architecture, vocation design, localization and validation |
| `tools/` | Static checks, packaging, reference retrieval and local utilities |
| `references/` | Pinned source URLs, versions and SHA-256 manifests |
| `dist/` | Generated release archives; ignored by Git |

Local dependencies, downloaded references, backups and raw runtime data are excluded from Git and release packages.

## License and credits

Original code is [MIT licensed](LICENSE). The bundled Noto Sans CJK SC font uses SIL OFL 1.1. Reference projects, pinned versions and licenses are listed in [sources](references/SOURCES.md) and [third-party notices](mod/THIRD_PARTY_NOTICES.md).
