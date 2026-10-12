"""Update this Mod's own scripts only, after closed-game and original-version checks."""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import sys
import zipfile
from datetime import datetime
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.stdout.reconfigure(encoding="utf-8")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--game-root", required=True, type=Path)
    parser.add_argument("--from-version", required=True)
    args = parser.parse_args()
    if not re.fullmatch(r"\d+\.\d+(?:\.\d+)?", args.from_version):
        raise SystemExit("无效版本")
    game = args.game_root.resolve()
    if not (game / "DD2.exe").is_file():
        raise SystemExit("目标不是 DD2 游戏目录")
    subprocess.run(["powershell.exe", "-NoProfile", "-Command",
                    "if (Get-Process -Name DD2 -ErrorAction SilentlyContinue) { exit 3 }"],
                   check=True, creationflags=subprocess.CREATE_NO_WINDOW, capture_output=True)
    version = re.search(r"^version=(\S+)$", (ROOT / "mod/modinfo.ini").read_text(encoding="utf-8"), re.M).group(1)
    source = ROOT / "mod"
    files = sorted((source / "reframework/autorun").rglob("*.lua"))
    planned = []
    # A user's edited installed scripts are never silently overwritten. A new module
    # may be added only if no installed file occupies its exact destination.
    with zipfile.ZipFile(ROOT / f"dist/DD2SkillStateManager-{args.from_version}-source.zip") as old:
        old_names = set(old.namelist())
        for path in files:
            relative = path.relative_to(source)
            target = (game / relative).resolve()
            if not target.is_relative_to(game):
                raise SystemExit("部署路径越出指定游戏目录")
            entry = "mod/" + relative.as_posix()
            original = hashlib.sha256(old.read(entry)).hexdigest() if entry in old_names else None
            if original is None:
                if target.exists():
                    raise SystemExit("新模块路径已有用户文件，保留用户内容：" + str(target))
            elif not target.is_file() or sha(target) != original:
                raise SystemExit("已安装文件与原版不一致，保留用户内容：" + str(target))
            planned.append((path, relative, target, original))
    backup = ROOT / "backups" / ("scripts-" + args.from_version + "-" + datetime.now().strftime("%Y%m%d-%H%M%S-%f"))
    for _, relative, target, original in planned:
        if original is None:
            continue
        saved = backup / relative
        saved.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(target, saved)
        assert sha(saved) == original, "原版备份不一致，未开始部署"
    started = []
    try:
        for path, relative, target, original in planned:
            if original is None:
                assert not target.exists(), "部署期间新模块路径出现其他文件"
            else:
                assert sha(target) == original, "部署期间原版文件发生变化"
            started.append((relative, target, original))
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(path, target)
            assert sha(target) == sha(path), "安装文件回读失败"
    except Exception:
        for relative, target, original in reversed(started):
            if original is None:
                # Exact file deletion only: target was verified inside game above.
                assert target.is_relative_to(game)
                target.unlink(missing_ok=True)
            else:
                shutil.copy2(backup / relative, target)
                assert sha(target) == sha(backup / relative), "脚本恢复失败，保留备份供人工恢复"
        raise
    report = {"version": version, "from_version": args.from_version, "game_root": str(game),
              "backup": str(backup), "files": [{"path": relative.as_posix(), "sha256": sha(target)}
                                              for _, relative, target, _ in planned],
              "scope": f"{len(files)} 个本 Mod Lua 脚本；未操作其他 Mod、字体、诊断或游戏存档"}
    (backup / "deployment.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report, ensure_ascii=False))


if __name__ == "__main__":
    main()
