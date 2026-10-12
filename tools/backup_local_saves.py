"""Copy complete local DD2 Steam save folders before manual runtime acceptance."""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.stdout.reconfigure(encoding="utf-8")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--steam-root", type=Path, required=True)
    args = parser.parse_args()
    subprocess.run(["powershell.exe", "-NoProfile", "-Command",
                    "if (Get-Process -Name DD2 -ErrorAction SilentlyContinue) { exit 3 }"],
                   check=True, capture_output=True, creationflags=subprocess.CREATE_NO_WINDOW)
    userdata = (args.steam_root / "userdata").resolve(strict=True)
    sources = sorted(path / "2054970" for path in userdata.iterdir()
                     if path.is_dir() and path.name.isdigit() and (path / "2054970/remote").is_dir())
    if not sources:
        raise SystemExit("未找到本机 DD2 存档；未创建空备份")
    backup = ROOT / "backups" / ("saves-before-edit-" + datetime.now().strftime("%Y%m%d-%H%M%S-%f"))
    if not backup.resolve().is_relative_to((ROOT / "backups").resolve()):
        raise SystemExit("备份路径越出工作区")
    entries = []
    for source in sources:
        source = source.resolve(strict=True)
        if not source.is_relative_to(userdata):
            raise SystemExit("存档来源越出 Steam userdata")
        for item in sorted(source.rglob("*")):
            if item.is_symlink() or item.is_junction():
                raise SystemExit("存档目录含链接，停止复制：" + str(item))
            if not item.is_file():
                continue
            relative = Path(source.parent.name) / "2054970" / item.relative_to(source)
            target = backup / relative
            if not target.resolve().is_relative_to(backup.resolve()):
                raise SystemExit("备份文件路径越界")
            initial = digest(item)
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(item, target)
            if digest(target) != initial or digest(item) != initial:
                raise SystemExit("复制期间存档改变，备份未确认为有效：" + str(item))
            entries.append({"path": relative.as_posix(), "source": str(item),
                            "bytes": target.stat().st_size, "sha256": initial})
    if not entries:
        raise SystemExit("存档目录为空，备份未确认为有效")
    manifest = {"created_at_utc": datetime.now(timezone.utc).isoformat(),
                "complete": True, "account_folders": len(sources), "entries": entries,
                "scope": "本机所有含 DD2 存档的 Steam 账号，其完整 2054970 目录；没有修改原文件或云端"}
    (backup / "backup-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"backup": str(backup), "accounts": len(sources),
                      "files": len(entries), "verified": True}, ensure_ascii=False))


if __name__ == "__main__":
    main()
