// popskill-main.jsx — 唯一主屏：卡片矩阵（02 的布局 × 01 紧凑账本的配色）
// - 独立能力 = 双列卡片，右侧两枚工具 pill（Claude / Codex）
// - 套装 = 通栏卡片，头部聚合分数，内部紧凑子项清单
// - 行内健康处理：✕/◐ 点击 → 修复弹层；版本 ↑ 徽标 → 一步更新；顶部横幅一键处理

// ── 卡片层样式（账本纸面色：#fafaf8 / #f4f2ec / 发丝线 #e8e6df / 电光蓝 #1f4ed8）──
const psCardStyles = {
  grid: { display: "grid", gridTemplateColumns: "1fr 1fr", gap: 10, padding: "16px 28px 28px", alignContent: "start" },
  card: { background: "#fff", borderRadius: 10, border: "1px solid #e8e6df", boxShadow: "0 1px 2px rgba(0,0,0,0.03)", padding: "13px 15px", display: "flex", gap: 12, position: "relative", minWidth: 0 },
  cardFlash: { borderColor: "#1f4ed8", background: "#eef4ff", transition: "background 1.2s, border-color 1.2s" },
  avatar: { width: 38, height: 38, borderRadius: 9, flexShrink: 0, background: "#f4f2ec", border: "1px solid #e8e6df", color: "#5e5a4e", fontSize: 15, fontWeight: 700, display: "flex", alignItems: "center", justifyContent: "center" },
  body: { flex: 1, minWidth: 0, display: "flex", flexDirection: "column", gap: 4 },
  nameRow: { display: "flex", alignItems: "center", gap: 8, minWidth: 0 },
  name: { fontSize: 13.5, fontWeight: 700, letterSpacing: "-0.015em", color: "#111", whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" },
  desc: { fontSize: 11.5, color: "#7c7869", lineHeight: 1.45 },
  meta: { fontSize: 11, color: "#9a9684", display: "flex", gap: 10, alignItems: "center", fontVariantNumeric: "tabular-nums", marginTop: 1, flexWrap: "wrap" },
  toggleCol: { display: "flex", flexDirection: "column", gap: 5, justifyContent: "center", minWidth: 118, flexShrink: 0 },
  pill: (status) => {
    const map = {
      on:     { bg: "rgba(31,78,216,0.06)", border: "#aabde8", c: "#1f4ed8" },
      off:    { bg: "transparent",          border: "#dcd9cf", c: "#9a9684" },
      stub:   { bg: "rgba(184,131,0,0.05)", border: "#dcc27a", c: "#8a6400" },
      broken: { bg: "rgba(192,24,24,0.04)", border: "#e0a3a3", c: "#c01818" },
    }[status] || { bg: "transparent", border: "#dcd9cf", c: "#9a9684" };
    return {
      display: "flex", alignItems: "center", gap: 7,
      padding: "4px 9px", borderRadius: 999,
      background: map.bg, border: `1px solid ${map.border}`,
      fontSize: 11, fontWeight: 600, color: map.c,
      cursor: "pointer", letterSpacing: "-0.005em", whiteSpace: "nowrap",
    };
  },
  pillGlyph: { fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace", fontSize: 11, width: 12, textAlign: "center", lineHeight: 1 },
  pillState: { marginLeft: "auto", fontSize: 10, fontWeight: 500, opacity: 0.75 },
  hoverActs: { display: "flex", gap: 2, marginLeft: "auto", flexShrink: 0 },

  bundleCard: { gridColumn: "1 / -1", flexDirection: "column", gap: 0, background: "#fcfbf6", borderRadius: 10, border: "1px solid #e8e6df", boxShadow: "0 1px 2px rgba(0,0,0,0.03)", padding: 0, position: "relative", overflow: "hidden" },
  bundleHead: { display: "flex", alignItems: "center", gap: 12, padding: "12px 15px", cursor: "pointer", background: "#f4f1e8", borderBottom: "1px solid #efede5" },
  aggBlock: { display: "flex", flexDirection: "column", alignItems: "center", gap: 3, minWidth: 52 },
  aggLabel: { fontSize: 9, fontWeight: 700, letterSpacing: "0.07em", textTransform: "uppercase", color: "#9a9684" },
  childList: { padding: "4px 8px 8px" },
  childHeader: { display: "flex", alignItems: "center", gap: 10, padding: "6px 8px 3px", fontSize: 9, fontWeight: 700, letterSpacing: "0.07em", textTransform: "uppercase", color: "#b3ae9e" },
  childRow: { display: "flex", alignItems: "center", gap: 10, padding: "4px 8px", borderRadius: 6, minWidth: 0 },
  colCell: { width: 44, display: "flex", justifyContent: "center", flexShrink: 0 },
  colVer: { width: 54, textAlign: "right", fontSize: 11, color: "#9a9684", fontVariantNumeric: "tabular-nums", flexShrink: 0 },
  colAct: { width: 22, flexShrink: 0, textAlign: "center" },
};

// ── 行内修复方案（对应 SPEC 修复逻辑）────────────────────
function psFixOptions(issue) {
  if (issue.kind === "stub") {
    return [
      { id: "verify", rec: true,  label: "完成校验并启用", desc: "校验 manifest 后将占位转为有效链接", result: "on",  toast: `已校验并启用 ${issue.capName} · ${issue.toolName}` },
      { id: "unlink", rec: false, label: "移除该侧占位",   desc: "撤掉占位 symlink，store 中保留文件", result: "off", toast: `已移除 ${issue.capName} 在 ${issue.toolName} 侧的占位` },
    ];
  }
  const opts = [];
  if (issue.latest) {
    opts.push({ id: "update", rec: true, label: `更新到 ${issue.latest} 并修复`, desc: `从 ${issue.sourceUrl} 拉取新版，重链全部 symlink`, result: "update", toast: `已更新 ${issue.entryName} → ${issue.latest} 并修复链接` });
  }
  if (issue.cause === "校验失败") {
    opts.push({ id: "repull", rec: !issue.latest, label: "从源重新拉取并校验", desc: "丢弃本地副本，按源重新校验安装", result: "on", toast: `已从源重新拉取 ${issue.capName}` });
    opts.push({ id: "trust",  rec: false, label: "跳过校验启用（降级）", desc: "信任当前文件，跳过 manifest 校验", result: "on", toast: `已跳过校验启用 ${issue.capName}（降级）` });
  } else {
    opts.push({ id: "relink", rec: !issue.latest, label: "重链到 store 中本地版本", desc: "指回 store 中现存的版本目录", result: "on", toast: `已重链 ${issue.capName} · ${issue.toolName}` });
    opts.push({ id: "repull", rec: false, label: "从源重新拉取", desc: `从 ${issue.sourceUrl} 重新获取该项`, result: "on", toast: `已从源重新拉取 ${issue.capName}` });
  }
  opts.push({ id: "unlink", rec: false, label: "移除该侧链接", desc: "撤掉这条 symlink，其他工具不受影响", result: "off", toast: `已移除 ${issue.capName} 在 ${issue.toolName} 侧的链接` });
  return opts;
}

function PsFixPopover({ pop, onApply, onClose }) {
  const opts = psFixOptions(pop);
  const W = 320;
  const left = Math.max(12, Math.min(pop.x - W / 2, 1280 - W - 12));
  const headColor = pop.kind === "stub" ? "#b88300" : "#c01818";
  const headSym = pop.kind === "stub" ? "◐" : "✕";
  const headLabel = pop.kind === "stub" ? "占位 (stub)" : pop.cause;
  return (
    <React.Fragment>
      <div style={{ position: "absolute", inset: 0, zIndex: 40 }} onClick={onClose}></div>
      <div data-screen-label="行内修复弹层" style={{
        position: "absolute", zIndex: 41, width: W,
        left, top: pop.flip ? undefined : pop.y + 6, bottom: pop.flip ? 820 - pop.y + 30 : undefined,
        background: "#fff", borderRadius: 9, border: "1px solid #dcd9cf",
        boxShadow: "0 12px 36px rgba(0,0,0,0.18)", overflow: "hidden",
        fontFamily: psStyles.win.fontFamily,
      }}>
        <div style={{ padding: "10px 14px 9px", borderBottom: "1px solid #efede5", background: "#fafaf8" }}>
          <div style={{ fontSize: 12.5, fontWeight: 700, color: headColor, display: "flex", alignItems: "center", gap: 6 }}>
            <span style={psStyles.mono}>{headSym}</span>{headLabel}
            <span style={{ color: "#111" }}>— {pop.capName}</span>
            <span style={{ color: "#9a9684", fontWeight: 500 }}>· {pop.toolName}</span>
          </div>
          {pop.sourceUrl && (
            <div style={{ ...psStyles.mono, fontSize: 10.5, color: "#7c7869", marginTop: 4 }}>
              ↗ {pop.sourceUrl}{pop.latest ? <span style={{ color: "#8a6400", fontWeight: 700 }}>  ↑ {pop.latest}</span> : null}
            </div>
          )}
        </div>
        <div style={{ padding: 6 }}>
          {opts.map(o => (
            <div key={o.id}
              onClick={() => onApply(o)}
              style={{
                padding: "8px 10px", borderRadius: 6, cursor: "pointer", marginBottom: 2,
                border: o.rec ? "1px solid #bcd8c2" : "1px solid transparent",
                background: o.rec ? "#f3f8f4" : "transparent",
              }}
              onMouseEnter={e => { if (!o.rec) e.currentTarget.style.background = "#f4f2ec"; }}
              onMouseLeave={e => { if (!o.rec) e.currentTarget.style.background = "transparent"; }}
            >
              <div style={{ fontSize: 12, fontWeight: 600, color: o.rec ? "#1a6b35" : "#111", display: "flex", gap: 6, alignItems: "center" }}>
                {o.label}
                {o.rec && <span style={{ fontSize: 9.5, fontWeight: 700, letterSpacing: "0.05em", color: "#1a6b35", border: "1px solid #bcd8c2", borderRadius: 3, padding: "1px 5px", background: "#fff", whiteSpace: "nowrap", flexShrink: 0 }}>推荐</span>}
              </div>
              <div style={{ fontSize: 11, color: "#7c7869", marginTop: 2, lineHeight: 1.45 }}>{o.desc}</div>
            </div>
          ))}
        </div>
      </div>
    </React.Fragment>
  );
}

// ── 空 store 态（首次启动）───────────────────────────────
function PsEmptyPane({ onAdd, onScan }) {
  return (
    <div data-screen-label="空 store 态" style={{ flex: 1, display: "flex", alignItems: "center", justifyContent: "center" }}>
      <div style={{ textAlign: "center", maxWidth: 420 }}>
        <div style={{ ...psStyles.mono, fontSize: 13, color: "#9a9684", marginBottom: 14 }}>~/.agents — 空</div>
        <div style={{ fontSize: 18, fontWeight: 700, letterSpacing: "-0.02em", marginBottom: 6 }}>还没有任何能力</div>
        <div style={{ fontSize: 12.5, color: "#6f6b5e", lineHeight: 1.6, marginBottom: 18 }}>
          粘贴一个 GitHub 仓库、npm 包或本地路径，<br />安装一次，挂载到所有 AI 工具。
        </div>
        <div style={{ display: "flex", gap: 8, justifyContent: "center" }}>
          <div style={psStyles.addBtn} onClick={onAdd}>+ 粘贴 URL 添加</div>
          <div style={{ ...psStyles.addBtn, background: "transparent", color: "#444", border: "1px solid #d8d5cb" }} onClick={onScan}>扫描本地目录</div>
        </div>
      </div>
    </div>
  );
}

// ── 工具 pill（独立能力卡片右列）──────────────────────────
function PsTogglePill({ status, label, onClick }) {
  const glyph = { on: "●", off: "○", stub: "◐", broken: "✕" }[status];
  const state = { on: "已激活", off: "未链接", stub: "占位", broken: "断链" }[status];
  return (
    <div style={psCardStyles.pill(status)} title="点击切换 / 处理" onClick={onClick}
      onMouseEnter={e => { e.currentTarget.style.boxShadow = "0 0 0 2px rgba(0,0,0,0.04)"; }}
      onMouseLeave={e => { e.currentTarget.style.boxShadow = "none"; }}>
      <span style={psCardStyles.pillGlyph}>{glyph}</span>
      <span>{label}</span>
      <span style={psCardStyles.pillState}>{state}</span>
    </div>
  );
}

// ── 主屏 ─────────────────────────────────────────────────
function PsMain({ db, winRef, flashId, expandAll, onToggle, onResolve, onApplyUpdate, onFixAll, onUpdateAll, onOpenAdd, onRemoveEntry, onOpenEditor, onScanLocal }) {
  const { useState, useRef, useEffect } = React;
  const types = ["全部", "Skill", "Agent", "MCP", "CLI", "Bundle"];
  const [query, setQuery] = useState("");
  const [typeFilter, setTypeFilter] = useState("全部");
  const [focused, setFocused] = useState(false);
  const [expanded, setExpanded] = useState(() => new Set(["feishu-suite"]));
  const [hoverId, setHoverId] = useState(null);
  const [pop, setPop] = useState(null);
  const searchRef = useRef(null);

  const stats = psStats(db.entries);
  const issues = psIssues(db.entries);
  const updates = psUpdates(db.entries);
  const toolName = (t) => (db.tools.find(x => x.id === t) || {}).name || t;

  useEffect(() => {
    const h = (e) => {
      if (e.key === "/" && document.activeElement !== searchRef.current && !/INPUT|TEXTAREA/.test(document.activeElement.tagName)) {
        e.preventDefault(); searchRef.current && searchRef.current.focus();
      }
      if (e.key === "Escape") setPop(null);
    };
    window.addEventListener("keydown", h);
    return () => window.removeEventListener("keydown", h);
  }, []);

  const toggleExpand = (id) => setExpanded(prev => { const n = new Set(prev); n.has(id) ? n.delete(id) : n.add(id); return n; });

  // Tweaks：展开全部套装
  const firstRun = useRef(true);
  useEffect(() => {
    if (firstRun.current) { firstRun.current = false; if (!expandAll) return; }
    setExpanded(expandAll ? new Set(db.entries.filter(psIsBundle).map(b => b.id)) : new Set());
  }, [expandAll]);

  // 单元格 / pill 点击 → 切换或打开修复弹层（坐标换算回 1280×820 设计空间）
  const onCellClick = (e, cap, tool, entry) => {
    e.stopPropagation();
    const status = cap[tool];
    if (status === "on" || status === "off") { onToggle(cap.id, tool); return; }
    const wr = winRef.current.getBoundingClientRect();
    const r = e.currentTarget.getBoundingClientRect();
    const k = wr.width / 1280;
    const x = (r.left + r.width / 2 - wr.left) / k;
    const y = (r.bottom - wr.top) / k;
    setPop({
      kind: status === "stub" ? "stub" : "broken",
      capId: cap.id, capName: cap.name, tool, toolName: toolName(tool),
      cause: cap.brokenCause || "断链",
      entryId: entry.id, entryName: entry.name,
      sourceUrl: entry.sourceUrl,
      latest: entry.latest && entry.latest !== entry.version ? entry.latest : null,
      x, y: Math.min(y, 800), flip: y > 520,
    });
  };

  const applyFix = (opt) => {
    if (opt.result === "update") onApplyUpdate(pop.entryId, opt.toast);
    else onResolve(pop.capId, pop.tool, opt.result, opt.toast);
    setPop(null);
  };

  // 过滤
  const q = query.trim().toLowerCase();
  const hit = (c) => !q || ((c.name || "") + " " + (c.desc || "") + " " + (c.author || "")).toLowerCase().includes(q);
  const filtering = q !== "" || typeFilter !== "全部";

  // 可见条目：套装条目（含命中子项集）+ 独立能力 + （类型过滤时）摊平的子项
  let items = [];
  if (typeFilter === "Bundle") {
    items = db.entries.filter(e => psIsBundle(e) && hit(e)).map(e => ({ kind: "bundle", entry: e, kids: e.children }));
  } else if (typeFilter !== "全部") {
    db.entries.forEach(e => {
      if (psIsBundle(e)) e.children.filter(c => c.type === typeFilter && hit(c)).forEach(c => items.push({ kind: "cap", entry: e, cap: c, fromBundle: e.name }));
      else if (e.type === typeFilter && hit(e)) items.push({ kind: "cap", entry: e, cap: e });
    });
  } else {
    db.entries.forEach(e => {
      if (psIsBundle(e)) {
        if (!q) items.push({ kind: "bundle", entry: e, kids: expanded.has(e.id) ? e.children : null });
        else if (hit(e)) items.push({ kind: "bundle", entry: e, kids: e.children });
        else { const mk = e.children.filter(hit); if (mk.length) items.push({ kind: "bundle", entry: e, kids: mk }); }
      } else if (hit(e)) items.push({ kind: "cap", entry: e, cap: e });
    });
  }
  const capCount = items.reduce((n, it) => n + (it.kind === "cap" ? 1 : it.entry.children.length), 0);

  const hoverAct = (visible, label, onClick, danger) => (
    <span style={{ ...psStyles.rowAction, visibility: visible ? "visible" : "hidden" }} title={label}
      onClick={onClick}
      onMouseEnter={e => { e.currentTarget.style.color = danger ? "#c01818" : "#1f4ed8"; }}
      onMouseLeave={e => { e.currentTarget.style.color = "#9a9684"; }}>{danger ? "✕" : "↗"}</span>
  );

  // 独立能力 / 摊平子项 → 双列卡片
  const renderCapCard = (it) => {
    const { cap, entry, fromBundle } = it;
    const hasUpdate = !fromBundle && entry.latest && entry.latest !== entry.version;
    const hovered = hoverId === cap.id;
    return (
      <div key={cap.id} style={{ ...psCardStyles.card, ...(flashId === cap.id ? psCardStyles.cardFlash : {}) }}
        onMouseEnter={() => setHoverId(cap.id)} onMouseLeave={() => setHoverId(null)}>
        <div style={psCardStyles.avatar}>{cap.name[0].toUpperCase()}</div>
        <div style={psCardStyles.body}>
          <div style={psCardStyles.nameRow}>
            <span style={psCardStyles.name}>{psHighlight(cap.name, q)}</span>
            <span style={psStyles.typeTag(cap.type)}>{cap.type}</span>
            <div style={psCardStyles.hoverActs}>
              {hoverAct(hovered, "在编辑器中打开", (e) => { e.stopPropagation(); onOpenEditor(cap.name); })}
              {!fromBundle && hoverAct(hovered, "移除", (e) => { e.stopPropagation(); onRemoveEntry(entry.id); }, true)}
            </div>
          </div>
          <div style={psCardStyles.desc}>{psHighlight(cap.desc, q)}</div>
          <div style={psCardStyles.meta}>
            <span>v{cap.version}</span>
            {hasUpdate && <span style={psStyles.updateBadge} title={`更新到 ${entry.latest}`} onClick={(e) => { e.stopPropagation(); onApplyUpdate(entry.id); }}>↑ {entry.latest}</span>}
            <span>{psHighlight(cap.author, q)}</span>
            {cap.tokens > 0 && <span>{(cap.tokens / 1000).toFixed(1)}k tokens</span>}
            {fromBundle && <span style={{ ...psStyles.mono, fontSize: 10 }}>⊂ {fromBundle}</span>}
            {!fromBundle && entry.sourceUrl && <span style={{ ...psStyles.mono, fontSize: 10, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis", maxWidth: 180 }}>↗ {entry.sourceUrl}</span>}
          </div>
        </div>
        <div style={psCardStyles.toggleCol}>
          <PsTogglePill status={cap.claude} label="Claude" onClick={(e) => onCellClick(e, cap, "claude", entry)} />
          <PsTogglePill status={cap.codex} label="Codex" onClick={(e) => onCellClick(e, cap, "codex", entry)} />
        </div>
      </div>
    );
  };

  // 套装 → 通栏卡片：头部聚合 + 子项紧凑清单
  const renderBundleCard = (it) => {
    const e = it.entry;
    const kids = it.kids;
    const open = !!kids;
    const hasUpdate = e.latest && e.latest !== e.version;
    const hovered = hoverId === e.id;
    const lastId = kids && kids.length ? kids[kids.length - 1].id : null;
    return (
      <div key={e.id} style={{ ...psCardStyles.card, ...psCardStyles.bundleCard, ...(flashId === e.id ? psCardStyles.cardFlash : {}) }}
        onMouseEnter={() => setHoverId(e.id)} onMouseLeave={() => setHoverId(null)}>
        <div style={psCardStyles.bundleHead} onClick={() => !q && toggleExpand(e.id)}>
          <span style={psStyles.disclosure}>{open ? "▼" : "▶"}</span>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={psCardStyles.nameRow}>
              <span style={{ ...psCardStyles.name, fontSize: 14 }}>{psHighlight(e.name, q)}</span>
              <span style={psStyles.typeTag("Bundle")}>Bundle</span>
              <span style={{ ...psStyles.tdMeta }}>{e.children.length} 项</span>
            </div>
            <div style={{ ...psCardStyles.desc, marginTop: 2 }}>{psHighlight(e.desc, q)} <span style={{ ...psStyles.mono, fontSize: 10, color: "#9a9684" }}>· ↗ {e.sourceUrl}</span></div>
          </div>
          <div style={psCardStyles.aggBlock}><span style={psCardStyles.aggLabel}>Claude</span><PsFraction agg={psAgg(e.children, "claude")} /></div>
          <div style={psCardStyles.aggBlock}><span style={psCardStyles.aggLabel}>Codex</span><PsFraction agg={psAgg(e.children, "codex")} /></div>
          <div style={{ fontSize: 11.5, color: "#7c7869", fontVariantNumeric: "tabular-nums", whiteSpace: "nowrap" }}>
            v{e.version}
            {hasUpdate && <span style={psStyles.updateBadge} title={`更新到 ${e.latest}`} onClick={(ev) => { ev.stopPropagation(); onApplyUpdate(e.id); }}>↑ {e.latest}</span>}
          </div>
          <div style={psCardStyles.hoverActs}>
            {hoverAct(hovered, "在编辑器中打开", (ev) => { ev.stopPropagation(); onOpenEditor(e.name); })}
            {hoverAct(hovered, "移除套装（含全部子项）", (ev) => { ev.stopPropagation(); onRemoveEntry(e.id); }, true)}
          </div>
        </div>
        {open && (
          <div style={psCardStyles.childList}>
            <div style={psCardStyles.childHeader}>
              <span style={{ flex: 1 }}></span>
              <span style={{ ...psCardStyles.colCell }}>Claude</span>
              <span style={{ ...psCardStyles.colCell }}>Codex</span>
              <span style={psCardStyles.colVer}>版本</span>
              <span style={psCardStyles.colAct}></span>
            </div>
            {kids.map(c => {
              const isLast = c.id === lastId;
              const ch = hoverId === c.id;
              return (
                <div key={c.id} style={{ ...psCardStyles.childRow, background: ch ? "#f4f2ec" : "transparent" }}
                  onMouseEnter={() => setHoverId(c.id)} onMouseLeave={() => setHoverId(e.id)}>
                  <div style={{ flex: 1, minWidth: 0, display: "flex", alignItems: "baseline", gap: 8 }}>
                    <span style={psStyles.childIndent}>{psTreeGlyph(isLast)}</span>
                    <span style={{ fontSize: 12, fontWeight: 600, color: "#222", whiteSpace: "nowrap" }}>{psHighlight(c.name, q)}</span>
                    <span style={psStyles.typeTag(c.type)}>{c.type}</span>
                    <span style={{ ...psCardStyles.desc, fontSize: 11, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{psHighlight(c.desc, q)}</span>
                  </div>
                  <span style={psCardStyles.colCell}><PsCell s={c.claude} title="点击切换 / 处理" onClick={(ev) => onCellClick(ev, c, "claude", e)} /></span>
                  <span style={psCardStyles.colCell}><PsCell s={c.codex} title="点击切换 / 处理" onClick={(ev) => onCellClick(ev, c, "codex", e)} /></span>
                  <span style={psCardStyles.colVer}>{c.version}</span>
                  <span style={psCardStyles.colAct}>{hoverAct(ch, "在编辑器中打开", (ev) => { ev.stopPropagation(); onOpenEditor(c.name); })}</span>
                </div>
              );
            })}
          </div>
        )}
      </div>
    );
  };

  if (db.entries.length === 0) {
    return <PsEmptyPane onAdd={onOpenAdd} onScan={onScanLocal} />;
  }

  return (
    <main data-screen-label="能力矩阵主屏" style={{ flex: 1, display: "flex", flexDirection: "column", minHeight: 0 }}>
      <div style={psStyles.hero}>
        <div style={{ minWidth: 0 }}>
          <h1 style={psStyles.h1}>能力矩阵</h1>
          <p style={psStyles.hsub}>{stats.bundles} 套装 · {stats.standalone} 独立能力 · Claude {stats.claudeOn} / Codex {stats.codexOn} 已激活</p>
        </div>
        <div style={psStyles.heroActions}>
          <div style={{ ...psStyles.searchPill, borderColor: focused ? "#1f4ed8" : "#dcd9cf", boxShadow: focused ? "0 0 0 3px rgba(31,78,216,0.12)" : "none" }}>
            <svg width="13" height="13" viewBox="0 0 13 13" fill="none"><circle cx="5.5" cy="5.5" r="4" stroke={focused ? "#1f4ed8" : "#9a9684"} strokeWidth="1.5"></circle><path d="M8.5 8.5l3 3" stroke={focused ? "#1f4ed8" : "#9a9684"} strokeWidth="1.5" strokeLinecap="round"></path></svg>
            <input ref={searchRef} value={query} onChange={e => setQuery(e.target.value)}
              onFocus={() => setFocused(true)} onBlur={() => setFocused(false)}
              placeholder="搜索名称 / 描述 / 作者…"
              style={{ flex: 1, minWidth: 0, border: "none", outline: "none", background: "transparent", fontSize: 12, color: "#111", fontFamily: "inherit", padding: 0 }} />
            {query
              ? <span onClick={() => setQuery("")} style={{ cursor: "pointer", color: "#9a9684", fontSize: 15, lineHeight: 1, paddingLeft: 2 }}>×</span>
              : <span style={{ ...psStyles.kbd, fontSize: 10, padding: "1px 5px" }}>/</span>}
          </div>
          <div style={psStyles.addBtn} onClick={onOpenAdd}>+ 添加</div>
        </div>
      </div>

      {(issues.length > 0 || updates.length > 0) && (
        <div style={psStyles.banner} data-screen-label="健康横幅">
          {issues.length > 0 && <span style={psStyles.bannerBroken}><span style={psStyles.mono}>✕</span>{issues.length} 个链接问题</span>}
          {issues.length > 0 && updates.length > 0 && <span style={{ color: "#d8cfae" }}>·</span>}
          {updates.length > 0 && <span style={psStyles.bannerUpdate}><span style={psStyles.mono}>↑</span>{updates.length} 个源可更新</span>}
          <span style={{ fontSize: 11.5, color: "#8a8268", whiteSpace: "nowrap" }}>点击 ✕ / ◐ / ↑ 可逐项处理</span>
          <span style={psStyles.spacer}></span>
          {issues.length > 0 && <div style={psStyles.bannerBtn(true)} onClick={onFixAll}>全部修复 ({issues.length})</div>}
          {updates.length > 0 && <div style={psStyles.bannerBtn(false)} onClick={onUpdateAll}>全部更新 ({updates.length})</div>}
        </div>
      )}

      <div style={psStyles.filterRow}>
        {types.map((t) => <div key={t} onClick={() => setTypeFilter(t)} style={psStyles.chip(t === typeFilter)}>{t}</div>)}
        <div style={psStyles.spacer}></div>
        <div style={{ fontSize: 11.5, color: filtering ? "#1f4ed8" : "#888", fontWeight: filtering ? 600 : 400, whiteSpace: "nowrap" }}>
          {filtering ? `${capCount} 项匹配` : "排序：类型 ↓"}
        </div>
      </div>

      <div style={{ flex: 1, overflow: "auto", background: "#fafaf8" }}>
        {items.length === 0 ? (
          <div style={{ textAlign: "center", padding: "64px 24px", color: "#9a9684" }}>
            <div style={{ fontSize: 13, fontWeight: 600, color: "#6f6b5e", marginBottom: 4 }}>无匹配结果</div>
            <div style={{ fontSize: 12 }}>没有能力匹配 “<span style={{ ...psStyles.mono, color: "#111" }}>{query}</span>”。试试别的关键词，或 + 添加。</div>
          </div>
        ) : (
          <div style={psCardStyles.grid}>
            {items.map(it => it.kind === "bundle" ? renderBundleCard(it) : renderCapCard(it))}
          </div>
        )}
      </div>

      {pop && <PsFixPopover pop={pop} onApply={applyFix} onClose={() => setPop(null)} />}
    </main>
  );
}

Object.assign(window, { PsMain, PsFixPopover, PsEmptyPane, psFixOptions, PsTogglePill });
