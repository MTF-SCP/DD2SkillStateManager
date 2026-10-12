# Contributing

Contributions to DD2 Skill Controller are welcome. Keep changes focused and describe the resulting behavior, affected character scope and validation performed.

## Reporting an issue

Include the game version/Steam build, REFramework version, Mod version, selected language, operation and target characters. Explain what you expected and what happened, including whether you confirmed the preview.

Use **Tools → Export diagnostics** when an interface or contract fails. Review exported data for private paths or character information before sharing an excerpt. Do not upload complete saves or backups. For layout issues, include the REFramework font size and a screenshot if available.

## Working on the project

Follow the [development guide](docs/DEVELOPMENT.md). Keep text UTF-8 and preserve the existing Lua module boundaries:

- UI submits portable requests; all live writes run through the update-stage controller.
- New writes need signature checks, a complete pre-operation snapshot, an explicit allowed-difference check and verified recovery.
- Do not guess memory offsets, skill IDs, valid grades or ownership.
- Keep English/Chinese presentation keys and format parameters consistent. Language must not alter editing rules.
- Document public contracts and explain non-obvious safety or compatibility constraints.

Run the static build checks for relevant changes and state any manual game verification separately. The build does not execute the Mod or simulate a game. Avoid unrelated changes and keep generated reports, raw diagnostics, downloaded references and backups out of Git.

## Pull requests

Describe the problem and the final behavior. Include the static-check result, any manual results and remaining limitations. Changes to editing rules should update the user guides and relevant design documents. There is no requirement to publish personal diagnostics to demonstrate a change.

Original contributions use the repository's MIT license. Preserve notices and licenses for third-party assets, and record pinned sources before adding reference material.
