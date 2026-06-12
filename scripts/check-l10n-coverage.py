#!/usr/bin/env python3
"""L() 取词覆盖率双向校验（v2.12）：
源码每处 L("…")（插值还原成 %lld/%@ 形态）必须能在 catalog 里找到 key；
catalog 每个 key 必须被源码引用。任一方向不一致即退出非零。
多行字符串 L(\"\"\" 与含内层引号的嵌套行解析不了，登记在 MANUAL_USED。"""
import json, re, glob, sys, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CALL = re.compile(r'L\("((?:[^"\\]|\\.)*)"\)')
INTERP = re.compile(r'\\\((?:[^()]|\((?:[^()]|\([^()]*\))*\))*\)')
PLACEHOLDER = re.compile(r'%(\d+\$)?(@|lld)')

MANUAL_USED = {
    # AppModel reportIssue 的 L(\"\"\" 多行模板
    "App: Popskill v%@\nmacOS: %@\n\n<!-- 描述问题。若 app 崩溃过，请附上 ~/Library/Logs/DiagnosticReports 里最新的 Popskill-*.ips 文件 -->\n",
    # StoreFS run() 超时：行内 ?? "" 的内层引号让正则截断
    "命令超时（%lld s）已终止：%@ %@",
}

src_keys = []
for f in glob.glob(f'{ROOT}/swift-app/Sources/Popskill/*.swift'):
    if f.endswith('Localization.swift'):
        continue
    for i, line in enumerate(open(f), 1):
        if line.strip().startswith('//') or 'L("""' in line:
            continue
        work = line
        while 'L("' in work:
            found = False
            for m in CALL.finditer(work):
                lit = m.group(1)
                segs = INTERP.split(lit)
                segs = [s.replace('\\n', '\n').replace('\\"', '"').replace('\\\\', '\\') for s in segs]
                src_keys.append((os.path.basename(f), i, segs))
                found = True
            if not found:
                break
            work = CALL.sub('⌧', work)

cat = json.load(open(f'{ROOT}/swift-app/l10n/Localizable.xcstrings'))
keys = set(cat['strings'].keys())

def try_key(k, segs):
    pos = 0
    for j, s in enumerate(segs):
        last = j == len(segs) - 1
        if s == '':
            if j == 0:
                continue                      # 开头是插值，占位由下一段的空隙检查吃掉
            m = PLACEHOLDER.match(k[pos:])
            if not m:
                return False                  # 尾段/相邻插值都必须正对一个 %-占位
            pos += m.end()
            if last:
                return pos == len(k)
            continue
        idx = k.find(s, pos)
        if idx < 0:
            return False
        if j == 0 and idx != 0:
            return False
        if j > 0 and idx != pos and not PLACEHOLDER.fullmatch(k[pos:idx]):
            return False
        pos = idx + len(s)
    return pos == len(k)

unmatched, used = [], set(MANUAL_USED)
for f, i, segs in src_keys:
    k = next((k for k in keys if try_key(k, segs)), None)
    if k:
        used.add(k)
    else:
        unmatched.append((f, i, segs))

print(f"l10n coverage: 源码 L() {len(src_keys)} 处 / catalog {len(keys)} key")
bad = False
if unmatched:
    bad = True
    print(f"== 源码有、catalog 缺（{len(unmatched)}）：==")
    for f, i, segs in unmatched:
        print(f"  {f}:{i}  {'⟨…⟩'.join(segs)!r}")
orphans = keys - used
if orphans:
    bad = True
    print(f"== catalog 有、源码未引用（{len(orphans)}）：==")
    for k in sorted(orphans):
        print(f"  {k!r}")
if not bad:
    print("l10n coverage ✓ 双向一致")
sys.exit(1 if bad else 0)
