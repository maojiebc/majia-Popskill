#!/usr/bin/env python3
"""往 docs/appcast.xml 置顶插入一个 Sparkle <item>。

带断言版（v2.5.0 事故教训：静默 no-op 会让发版链产生假成功）：
- 新版本已存在 → 报错退出
- 找不到插入锚点（channel 内第一个 <item> 或 </channel>）→ 报错退出
- 写后复读校验新 item 在顶部 → 否则报错退出

用法:
  scripts/append-appcast.py --version 2.5.0 --build 250 \
      --sig <edSignature> --length <bytes> --title "标题" --html-notes <file|->
"""
import argparse
import pathlib
import sys

APPCAST = pathlib.Path(__file__).resolve().parent.parent / "docs/appcast.xml"
REPO_DL = "https://github.com/maojiebc/majia-Popskill/releases/download"

TEMPLATE = """    <item>
      <title>v{version}</title>
      <pubDate>{pubdate}</pubDate>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <description><![CDATA[
{notes}
      ]]></description>
      <enclosure
        url="{repo}/v{version}/Popskill-{version}.dmg"
        sparkle:version="{build}"
        sparkle:shortVersionString="{version}"
        sparkle:edSignature="{sig}"
        length="{length}"
        type="application/octet-stream"/>
    </item>
"""


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--version", required=True)
    ap.add_argument("--build", required=True)
    ap.add_argument("--sig", required=True)
    ap.add_argument("--length", required=True, type=int)
    ap.add_argument("--pubdate", required=True, help="RFC822，如 'Wed, 10 Jun 2026 17:00:00 +0000'")
    ap.add_argument("--html-notes", required=True, help="HTML 片段文件，- 为 stdin")
    args = ap.parse_args()

    if not args.sig.strip() or len(args.sig) < 60:
        sys.exit(f"[appcast] sig 看起来不对（长度 {len(args.sig)}）——上游取值失败？")
    if args.length < 1_000_000:
        sys.exit(f"[appcast] length={args.length} 小得离谱——stat 失败？")

    notes = (sys.stdin.read() if args.html_notes == "-"
             else pathlib.Path(args.html_notes).read_text())

    s = APPCAST.read_text()
    if f"<title>v{args.version}</title>" in s:
        sys.exit(f"[appcast] v{args.version} 已存在，拒绝重复插入")

    item = TEMPLATE.format(version=args.version, build=args.build, sig=args.sig,
                           length=args.length, pubdate=args.pubdate,
                           notes=notes.rstrip(), repo=REPO_DL)

    anchor = "    <item>"
    idx = s.find(anchor)
    if idx < 0:
        anchor = "  </channel>"
        idx = s.find(anchor)
        if idx < 0:
            sys.exit("[appcast] 找不到插入锚点（无 <item> 也无 </channel>）")
    s = s[:idx] + item + s[idx:]

    APPCAST.write_text(s)

    # 写后复读校验
    again = APPCAST.read_text()
    first_title = again.split("<title>v", 2)
    if len(first_title) < 2 or not first_title[1].startswith(args.version):
        sys.exit("[appcast] 写后校验失败：新版本不在顶部")
    print(f"[appcast] ok — v{args.version} 置顶，length={args.length}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
