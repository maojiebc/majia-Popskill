#!/usr/bin/env python3
"""hot-skills.json → swift-app/Sources/Popskill/CatalogHot.swift

热门 skill 目录数据的生成器（v2.14）。数据来源：skills.sh 排行 + anthropics/skills
官方库 + awesome 列表（抓取脚本见 docs/dev/hot-skills-pipeline.md）。

用法：scripts/gen-catalog-hot.py <hot-skills.json>
- 排除 Catalog.swift 手工段已有的 key（手工版优先，重复浪费二进制）
- 名称必须过 sanitize（与 app 同规则）；简介截长；引号转义
- 全文件重生成——别手改 CatalogHot.swift，改这里或改数据源
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "swift-app/Sources/Popskill/Catalog.swift"
OUT = ROOT / "swift-app/Sources/Popskill/CatalogHot.swift"

def swift_str(s: str, limit: int) -> str:
    s = " ".join(s.split())[:limit]
    return s.replace("\\", "\\\\").replace('"', '\\"')

def main(src: str) -> None:
    data = json.load(open(src))
    manual = set(re.findall(r'^\s*"([^"]+)":\s*\.init', CATALOG.read_text(), re.M))
    seen, rows = set(), []
    for it in sorted(data, key=lambda x: -(x.get("hot") or 0)):
        name = (it.get("name") or "").strip()
        zh, en = (it.get("zh") or "").strip(), (it.get("en") or "").strip()
        if not name or not zh or name in manual or name in seen:
            continue
        if name.startswith(".") or "/" in name or ".." in name or " " in name:
            continue
        seen.add(name)
        en_part = f', en: "{swift_str(en, 90)}"' if en else ""
        rows.append(f'        "{name}": .init(desc: "{swift_str(zh, 60)}"{en_part}),')
    body = "\n".join(rows)
    OUT.write_text(f"""import Foundation

// 热门 skill 目录（脚本生成，勿手改——scripts/gen-catalog-hot.py 全文件重生成）。
// 覆盖 skills.sh 排行 / anthropics 官方 / awesome 列表的常用 skill：
// 装了它们的用户不用等我们手工收录就有干净的双语一句话简介。
// 手工精选在 Catalog.swift，同名时手工版优先（Catalog.entry 的查找顺序保证）。

enum CatalogHot {{
    static let skills: [String: CatalogEntry] = [
{body}
    ]
}}
""")
    print(f"生成 {OUT.name}: {len(rows)} 条（数据 {len(data)} 条，排除手工段 {len(manual)} key 与非法名）")

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "hot-skills.json")
