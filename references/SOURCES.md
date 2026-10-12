# Sources and licenses

Pinned URLs, SHA-256 and byte counts are recorded in [manifest.json](manifest.json) and [font-manifest.json](font-manifest.json). Reference code/data is used for local API and structure research; it is not embedded in the Mod implementation or redistributed in release ZIPs. The font is a runtime asset distributed under its own license.

## Pinned projects

| Source | Commit | Purpose | License |
| --- | --- | --- | --- |
| [REFramework](https://github.com/praydog/REFramework/tree/d1461375aee4ec3f313170f8eaad12064eb542d9) | `d1461375aee4ec3f313170f8eaad12064eb542d9` | Lua SDK/ImGui/JSON/FS/callback bindings and managed array handling | MIT; downloaded `REFramework/LICENSE` |
| [Skill Maker](https://github.com/alphazolam/Skill-Maker/tree/b9d5d51e369dc19873adfb05eb7967e53388b403) | `b9d5d51e369dc19873adfb05eb7967e53388b403` | Actor-access and REFramework usage reference | MIT; downloaded `Skill-Maker/LICENSE` |
| [dd2-content-editor](https://github.com/kagenocookie/dd2-content-editor/tree/eabf3fc228eecbe5bff8a3a1f0d62384f84e51cd) | `eabf3fc228eecbe5bff8a3a1f0d62384f84e51cd` | GUID/message interface reference | MIT; downloaded `dd2-content-editor/LICENSE` |
| [REE-Lib-Resources](https://github.com/kagenocookie/REE-Lib-Resources/tree/d40f266c9521eacb3232ebba0e97c9947a888a5b) | `d40f266c9521eacb3232ebba0e97c9947a888a5b` | Resource and reflected-enum metadata | MIT; downloaded `REE-Lib-Resources/LICENSE` |
| [REasy DD2 type data](https://github.com/kagenocookie/REasy/blob/103397ac389babfb852558da682e69b44d16fe0c/resources/data/dumps/rszdd2.json) | `103397ac389babfb852558da682e69b44d16fe0c` | Serialized field cross-checks | No root license text obtained for the pinned revision; local reference only, excluded from releases |
| [Dear ImGui](https://github.com/ocornut/imgui/tree/85b2fe8486190fa9326565a2fb5fccb6caea4396) | `85b2fe8486190fa9326565a2fb5fccb6caea4396` | REFramework's pinned ImGui header, version 1.92.0, for style-color constants | MIT; downloaded `REFramework/imgui-LICENSE.txt` |
| [Noto CJK](https://github.com/notofonts/noto-cjk/tree/f8d157532fbfaeda587e826d4cd5b21a49186f7c) | `f8d157532fbfaeda587e826d4cd5b21a49186f7c` | Unmodified Noto Sans CJK SC Regular font, installed under a Mod-specific filename | SIL OFL 1.1; license bundled with the font |

## Official REFramework documentation

- [SDK](https://refdocs.praydog.com/api/sdk.html): type/method/field reflection and native calls.
- [ImGui](https://refdocs.praydog.com/api/imgui.html): widgets, fonts and local style stacks.
- [Callbacks](https://refdocs.praydog.com/api/re.html): update-stage writes and UI rendering.
- [Best practices](https://refdocs.praydog.com/api/general/best-practices.html): descriptor caching and reacquiring unstable game objects.
- [JSON](https://refdocs.praydog.com/api/json.html) and [FS](https://refdocs.praydog.com/api/fs.html): portable data and paths relative to `reframework/data`.
- [SystemArray](https://refdocs.praydog.com/api/types/SystemArray.html): managed elements and typed array access.

Documentation links complement pinned implementation sources; web pages are not treated as immutable versioned source artifacts.

## Runtime evidence and implementation boundaries

Local runtime exports supply actual method signatures, acquisition semantics, slot layouts, vocation progress and protection/recovery contracts. They are private evidence, not repository assets or proof that every editing scenario succeeded. See [validation](../docs/RUNTIME_VALIDATION.md).

Array access uses managed boxed integers rather than guessed payload offsets. Language detection uses reflected names/signatures. Qualification locking requires a verified bitmap mapping. EX variants are separated from ordinary saved levels and remain supplied by weapon traits.

The pinned Lua binding exposes numeric ImGui style-color slots. The matching header defines Text=0, Button=21, ButtonHovered=22 and ButtonActive=23; static checks verify those positions. `push_style_color` integers use native ABGR, whereas `text_colored` uses ARGB. Local stacks are restored after drawing.

## Reproducing reference downloads

Run `python tools/fetch_references.py` from the repository root. Only hashed manifest entries are fetched; existing matching files are retained. Downloaded reference implementations, game data, raw runtime reports and backups are excluded from Git and both release ZIPs. The installed Mod never reads `references/`.
