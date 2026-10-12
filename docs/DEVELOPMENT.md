# Development

## Setup and build

Use Python 3.12 and run from the repository root:

```powershell
python -m pip install --target .tools/python -r tools/requirements-static.txt
python tools/fetch_references.py
python tools/build.py
```

`fetch_references.py` retrieves only pinned URLs recorded in the reference/font manifests and verifies SHA-256. Downloaded references stay local. The font is a runtime asset and retains its OFL license.

`build.py` runs the static gate before creating:

- `dist/DD2SkillStateManager-<version>-install.zip`
- `dist/DD2SkillStateManager-<version>-source.zip`
- `dist/SHA256SUMS.txt`

The version comes from `mod/modinfo.ini`. The installation ZIP contains root `modinfo.ini`, `reframework/autorun`, fonts/licenses and user guides. The source ZIP contains the original project, tools and source manifests. Both exclude private runtime data, backups, dependencies and downloaded reference code.

For static checks without packaging:

```powershell
python tools/static_check.py
```

Checks load/parse Lua syntax without running Mod chunks. They inspect module/API references, mutation boundaries, localization keys/format parameters, encoding, source hashes and installation inputs. If local runtime exports are available in `docs/runtime/diagnostic-*.json`, their signatures provide additional evidence; a clean checkout explicitly records their absence. Neither check nor build starts the game or runs game simulations.

Generated reports are written to `docs/`; the installation tree receives a static-report copy. They are ignored by Git and can be regenerated. ZIP stream, entry and SHA-256 checks are reported separately in `PACKAGE_CHECK_REPORT.md`.

## Project structure

| Path | Purpose |
| --- | --- |
| `mod/reframework/autorun/DD2SkillStateManager.lua` | Controller and callbacks |
| `mod/reframework/autorun/DD2SkillStateManager/` | Access, catalogue, transactions, localization, UI and diagnostics |
| `mod/reframework/fonts/` | CJK font and OFL license |
| `docs/` | Design and validation documents |
| `tools/` | Development utilities |
| `references/` | Source/license provenance and pinned manifests |
| `.tools/`, `backups/`, `docs/runtime/` | Local dependencies and private data; ignored |

See [architecture](ARCHITECTURE.md), [vocation design](PROGRESS.md), [localization](LOCALIZATION.md) and [validation](RUNTIME_VALIDATION.md).

## Optional local utilities

These commands require a closed game and do not run as part of the build. Replace the example paths and version with your own installation:

```powershell
python tools/backup_local_saves.py --steam-root "C:\Program Files (x86)\Steam"
python tools/deploy_local.py --game-root "D:\SteamLibrary\steamapps\common\Dragons Dogma 2" --from-version 1.0
```

Save backup copies all detected local DD2 account directories and verifies source/copy hashes; it does not edit original saves or Steam Cloud. Deployment verifies the installed previous scripts against `dist/DD2SkillStateManager-<previous-version>-source.zip`, backs them up, then replaces only this Mod's Lua files. A new module can be added only when its destination is absent. Keep the previous source ZIP available until deployment completes. Fonts and other Mods are not updated by this helper.

Manual installation of the installation ZIP remains available. Do not edit or distribute the local backup directories.

## Maintenance

Keep all text UTF-8. Reference manifests are provenance records: update their URL, version and hash together when deliberately adopting a new source. Do not check downloaded game data into the repository.

Source changes must preserve separate skill and vocation transaction rules, portable previews and one update-stage write dispatcher. Report static validation and manual in-game observations separately. See [contributing](../CONTRIBUTING.md).
