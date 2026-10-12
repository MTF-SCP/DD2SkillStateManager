# Localization and font layout

## Language policy

`auto` is the default. Reflected game text language names `SimplelifiedChinese` and `TransitionalChinese` map to `zh`; every other/unknown language or unavailable detector maps to `en`. These spellings come from `via.Language`, rather than guessed numeric constants.

The top selector always offers Auto, 中文 and English. Manual selection takes precedence and is saved immediately to `reframework/data/DD2SkillStateManager/settings.json`. Chinese UI and game text use Simplified Chinese. The Mod never changes game text language, voice language or system settings.

## Responsibilities and game text

`i18n.lua` contains only static English/Chinese dictionaries, formatting and structured notices/skip reasons. It does not access game objects or ImGui. The UI translates portable role IDs, field IDs, booleans and grades at render time. Stable `###` widget IDs do not change with displayed language.

The controller reads the optional GUI text-language getter in the update stage, with exact reflected instance/no-argument/`via.Language` signature checks. An unavailable getter falls back to English without disabling editing. Manual override remains available.

Vocation names, skill names and descriptions use `via.gui.message.get(System.Guid, via.Language)` with the selected language. Missing text falls back to enum names or IDs. Changing language cancels previews, resets name search and rebuilds localized text caches while retaining selected IDs.

Display text is separate from valid-grade verification. Native upgrade-description checks remain in `validation_description`; selecting English must not enable a grade rejected under the verified game data. Catalogue stamps exclude translated strings, and game-language changes invalidate text-dependent caches.

## Font and layout

Noto Sans CJK SC is bundled with its OFL license to cover Chinese and English. It loads once; every draw reads `imgui.get_default_font_size()` and uses `imgui.push_font(font, size)`. There is no independent Mod size setting.

Labels, role columns, wrapping and preview widths use current font measurements. Cached glyph widths are invalidated on size/language change. Narrow previews stack vertically and retain vocation names. ImGui font, table, disabled and local color stacks are closed even on drawing errors.

Confirm buttons are green, discard/locking/deletion red, and setup actions blue. Text still names each action explicitly; color is not the sole indicator. Pending previews display a reminder both near the top and before confirmation.

## Adding or editing text

Keep English and Chinese keys/format parameters consistent, with portable field/role IDs independent of wording. Put technical errors, signatures and internal paths in logs/diagnostics, not in user-facing labels. Update both user guides when interaction changes.

Static validation parses both dictionaries with the Lua AST, checks key parity, placeholders and UI references, and verifies pinned API/enum evidence. It does not execute translation or UI functions. Font rendering, auto-detection, saved preferences and narrow/large-font layouts need manual observation; see [validation](RUNTIME_VALIDATION.md).
