# Third-party notices

The original Lua implementation is distributed under the MIT license in `LICENSE`. The Mod depends on REFramework and does not embed the implementations of other Mods or game-type datasets.

## Bundled font

Noto Sans CJK SC Regular comes from notofonts/noto-cjk commit `f8d157532fbfaeda587e826d4cd5b21a49186f7c`. It is installed as `reframework/fonts/DD2SkillStateManager-CJK.otf`; the font content is unmodified.

The font uses SIL Open Font License 1.1. The full license is included as `reframework/fonts/DD2SkillStateManager-CJK-LICENSE.txt` and must remain with the font.

## Development references

REFramework, Skill Maker, dd2-content-editor, REE-Lib-Resources and Dear ImGui are MIT-licensed reference projects. Their pinned versions, downloaded license texts, URLs and hashes are listed in the source project's `references/SOURCES.md` and manifests. Reference implementations are not embedded in release archives.

The pinned REasy DD2 type dataset has no obtained root license text and is retained only as a local reference; it is not redistributed. Dear ImGui style-color constants are checked against the version referenced by REFramework; its original header remains a development reference.
