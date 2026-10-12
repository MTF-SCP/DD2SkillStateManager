# DD2 Skill Controller

[中文](README-zh-CN.md) · [Installation and usage](mod/README-en.md)

A REFramework Lua Mod for Dragon's Dogma 2 on PC Steam. Edit active weapon skill acquisition and valid levels for the Arisen and Main Pawn, with synchronized transactions, automatic unequipping and native skill discovery.

Version **1.0** fixes a guard fingerprint that rolled back valid vocation/JP changes, adds one-action unlocking of all eligible vocations, and separates current information from selected-vocation editing. Confirmation is green, discard/locking are red, and pending changes remain clearly marked. Vocation qualification, rank and JP support Arisen/Main Pawn/both targeting. Vocation unlocking preserves first-change history; locking requires changing away from the vocation in game. Rank changes retain skill and augment acquisition. The font follows REFramework size settings in real time. English and Chinese are supported. Auto reads the game's text language: Chinese maps to Chinese; all other or unknown languages map to English. A persistent manual override is available at the top. Vocation/skill names and descriptions use explicitly localized game text. Language selection does not change valid-level or acquisition rules. Weapon EX remains game-managed.

## Project layout

| Path | Contents |
| --- | --- |
| `mod/` | Installable runtime, nine Lua files, licensed font and bilingual documentation |
| `tools/` | Static checks, packaging, pinned-reference fetching and local deployment |
| `docs/` | Architecture, localization design and validation status |
| `references/` | Provenance and pinned hash manifests; downloaded reference data stays local |
| `dist/` | Generated installation/source ZIPs; ignored by Git |
| `backups/`, `docs/runtime/` | Private save/script backups and raw game reports; ignored by Git |
| `.tools/` | Local check dependencies; ignored by Git and not required by the Mod |

The repository root is `DD2_SkillController`. The original project was moved here with 339 file hashes verified. A root MIT license and `.gitignore` are included. No repository has been published; upload this directory as the future GitHub project and keep the ignore rules. Installation ZIPs can be attached separately to releases.

## Build

From the project root, with Python 3.12:

```text
python -m pip install --target .tools/python -r tools/requirements-static.txt
python tools/fetch_references.py
python tools/static_check.py
python tools/build.py
```

The checker parses/compiles Lua without executing Mod code, simulating a game environment or running a test suite. It checks module/API references, localization keys/format placeholders, UTF-8, mutation boundaries and package inputs. Existing local runtime reports provide additional signature evidence; a clean checkout records their absence explicitly.

Third-party reference code and data are downloaded by pinned hashes for local research. They are not redistributed in either ZIP. The bundled Noto CJK font retains its OFL license. Private saves, reports, dependencies and historical archives are excluded from release packaging and Git tracking.

Local deployment requires a closed game and verifies the installed previous version before replacing only this Mod's scripts. New modules are added only when the destination is absent. Save backup tools copy complete local save directories and never edit the originals or Steam Cloud.

Ordinary editing and an automatic-unequip deletion have successful game logs. The latest 0.4.0 diagnostic confirms both actors’ progress interfaces and protection/recovery layouts. Fixed 1.0 writes, bulk unlocking and the revised interface still require in-game confirmation. See [runtime validation](docs/RUNTIME_VALIDATION.md), [localization](docs/LOCALIZATION.md), [architecture](docs/ARCHITECTURE.md) and [sources](references/SOURCES.md).
