"""Build and inspect distributable ZIPs; includes no runtime tests or game installation."""
from __future__ import annotations

import hashlib
import json
import re
import shutil
import zipfile
from pathlib import Path

from static_check import ROOT, run


def package(source_files, path):
    expected = {}
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for source, name in sorted(source_files, key=lambda item: item[1]):
            data = source.read_bytes()
            expected[name] = hashlib.sha256(data).hexdigest()
            archive.writestr(name, data)
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None, "ZIP 压缩流损坏"
        assert set(archive.namelist()) == set(expected), "包内文件不一致"
        assert len(archive.namelist()) == len(expected), "重复 ZIP 条目"
        for name in archive.namelist():
            assert not name.startswith("/") and ".." not in Path(name).parts
            assert hashlib.sha256(archive.read(name)).hexdigest() == expected[name], name
    return {"file": path.name, "bytes": path.stat().st_size,
            "sha256": hashlib.sha256(path.read_bytes()).hexdigest(), "entries": expected}


def main():
    result = run()
    if not result["passed"]:
        raise SystemExit("静态检查失败，未发布新安装包")
    shutil.copy2(ROOT / "docs/STATIC_CHECK_REPORT.md", ROOT / "mod/STATIC_CHECK_REPORT.md")
    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    version = re.search(r"^version=(\S+)$", (ROOT / "mod/modinfo.ini").read_text(encoding="utf-8"), re.M).group(1)
    installation = [(p, p.relative_to(ROOT / "mod").as_posix()) for p in (ROOT / "mod").rglob("*") if p.is_file()]
    names = {name for _, name in installation}
    assert "modinfo.ini" in names and "reframework/autorun/DD2SkillStateManager.lua" in names
    assert "reframework/fonts/DD2SkillStateManager-CJK-LICENSE.txt" in names
    assert not any(name.startswith(("references/", "tools/", "reframework/data/", ".tools/")) for name in names)
    installer = package(installation, dist / f"DD2SkillStateManager-{version}-install.zip")
    # Source ZIP contains original project + source pointers, never unlicensed dump data.
    source_files = []
    for folder in ("mod", "tools", "docs"):
        for path in (ROOT / folder).rglob("*"):
            if path.is_file() and "__pycache__" not in path.parts and path.suffix != ".pyc":
                if path.is_relative_to(ROOT / "docs/runtime"):
                    continue  # User's raw game diagnostics stay local, outside release archives.
                if path.name in {"package-manifest.json", "PACKAGE_CHECK_REPORT.md"}:
                    continue  # Avoid stale reports and recursive archive hashes.
                source_files.append((path, path.relative_to(ROOT).as_posix()))
    for name in ("README.md", "README-zh-CN.md", "LICENSE", ".gitignore", "references/SOURCES.md", "references/manifest.json", "references/font-manifest.json"):
        source_files.append((ROOT / name, name))
    source = package(source_files, dist / f"DD2SkillStateManager-{version}-source.zip")
    manifest = {"version": version, "runtime_verified": False, "archives": [installer, source]}
    (ROOT / "docs/package-manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    report = ["# 安装包检查报告", "", "结果：通过。两份 ZIP 压缩流、文件树、重复条目与逐文件 SHA-256 核验一致。", "",
              "| 文件 | 条目数 | 字节 | SHA-256 |", "| --- | --- | --- | --- |"]
    for item in (installer, source):
        report.append(f"| {item['file']} | {len(item['entries'])} | {item['bytes']} | `{item['sha256']}` |")
    report += ["", "安装包包含 reframework/autorun、完整模块、CJK 字体及 OFL、modinfo.ini、MIT 和中文说明。无诊断数据、参考源码、Python 或检查库。", "",
               "源码 ZIP 包含原创项目与开发工具；外部参考源码/资料在本地 references，未混入发布包。可按来源清单下载。", "",
               "源码项目位于 DD2_SkillController，提供根许可证和 Git 忽略规则；私有存档、运行时报告、下载资料及本地库均不进入源码 ZIP。中英说明随包提供。", "",
               "Fluffy 的文件布局静态符合根目录 modinfo.ini + reframework 结构，管理器实际部署尚未人工验证。0.1.3 普通编辑及 0.2.0 一槽自动卸装已有成功日志；1.0 已修复 0.4.0 误回滚并增加批量解锁/提示/配色；修复后职业/JP 行为和新界面待游戏复核，见 RUNTIME_VALIDATION.md。"]
    (ROOT / "docs/PACKAGE_CHECK_REPORT.md").write_text("\n".join(report) + "\n", encoding="utf-8")
    (dist / "SHA256SUMS.txt").write_text("\n".join(f"{item['sha256']}  {item['file']}" for item in (installer, source)) + "\n", encoding="utf-8")
    print(json.dumps({"archives": [{key: item[key] for key in ("file", "bytes", "sha256")} for item in (installer, source)]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
