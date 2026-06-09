// popskill-ui.jsx — 共享视觉语言（账本风格：发丝线、单一电光蓝、紧凑密度）
// 自 v1 ledger 继承，砍掉侧栏后主区铺满整窗。

const psStyles = {
  win: {
    width: 1280, height: 820, borderRadius: 10, overflow: "hidden",
    background: "#fafaf8", position: "relative",
    boxShadow: "0 0 0 1px rgba(0,0,0,0.18), 0 24px 60px rgba(0,0,0,0.32)",
    display: "flex", flexDirection: "column",
    fontFamily: 'Inter, -apple-system, "Helvetica Neue", "PingFang SC", sans-serif',
    color: "#111",
  },
  mono: { fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace" },
  spacer: { flex: 1 },

  // ── titlebar / statusbar ──────────────────────────────
  titlebar: {
    height: 38, flexShrink: 0, display: "flex", alignItems: "center",
    padding: "0 14px", gap: 10,
    borderBottom: "1px solid #e8e6df", background: "#f4f2ec",
  },
  lights: { display: "flex", gap: 8 },
  light: (c) => ({ width: 12, height: 12, borderRadius: "50%", background: c, boxShadow: "inset 0 0 0 0.5px rgba(0,0,0,0.12)" }),
  titleLabel: { fontSize: 12.5, fontWeight: 600, letterSpacing: "-0.005em", color: "#111", marginLeft: 2 },
  kbd: { fontSize: 11, color: "#666", padding: "2px 6px", border: "1px solid #d8d5cb", borderRadius: 4, background: "#fff", fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace" },
  syncChip: { display: "flex", alignItems: "center", gap: 6, fontSize: 11, color: "#5a7a5f", padding: "2px 9px 2px 8px", border: "1px solid #cfe0d2", borderRadius: 999, background: "#f3f8f4", fontWeight: 500, whiteSpace: "nowrap", flexShrink: 0 },
  syncDot: { width: 6, height: 6, borderRadius: "50%", background: "#1a9a4e" },
  statusbar: {
    height: 26, flexShrink: 0, display: "flex", alignItems: "center", gap: 9,
    padding: "0 16px", borderTop: "1px solid #e8e6df", background: "#f4f2ec",
    fontSize: 11, color: "#7c7869", whiteSpace: "nowrap", overflow: "hidden",
  },
  sbMono: { fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace", color: "#5e5a4e" },
  sbDim: { color: "#c4bfb0" },
  sbLink: { color: "#1f4ed8", cursor: "pointer", fontWeight: 500 },
  syncChipSm: { display: "flex", alignItems: "center", gap: 6, color: "#5a7a5f", fontWeight: 500, whiteSpace: "nowrap", flexShrink: 0 },

  // ── hero / 工具行 ─────────────────────────────────────
  hero: { padding: "18px 28px 14px", borderBottom: "1px solid #e8e6df", display: "flex", alignItems: "flex-start", justifyContent: "space-between", gap: 20 },
  h1: { fontSize: 25, fontWeight: 700, letterSpacing: "-0.025em", margin: 0, marginBottom: 5, lineHeight: 1.1 },
  hsub: { fontSize: 12.5, color: "#6f6b5e", margin: 0, lineHeight: 1.5 },
  heroActions: { display: "flex", alignItems: "center", gap: 8, flexShrink: 0, paddingTop: 2 },
  searchPill: { display: "flex", alignItems: "center", gap: 7, width: 220, height: 30, padding: "0 11px", borderRadius: 7, border: "1px solid #dcd9cf", background: "#fff", color: "#9a9684", fontSize: 12 },
  addBtn: { display: "flex", alignItems: "center", gap: 6, height: 30, padding: "0 14px", borderRadius: 7, background: "#111", color: "#fff", fontSize: 12.5, fontWeight: 600, letterSpacing: "-0.005em", cursor: "pointer", whiteSpace: "nowrap" },

  filterRow: { display: "flex", alignItems: "center", gap: 6, padding: "10px 28px", borderBottom: "1px solid #e8e6df" },
  chip: (active) => ({
    fontSize: 11.5, fontWeight: 500, padding: "4px 9px", borderRadius: 4, whiteSpace: "nowrap", flexShrink: 0,
    color: active ? "#fff" : "#444",
    background: active ? "#111" : "transparent",
    border: active ? "1px solid #111" : "1px solid #d8d5cb",
    cursor: "pointer", letterSpacing: "-0.005em",
  }),

  // ── 健康横幅（有问题 / 可更新时出现）──────────────────
  banner: {
    display: "flex", alignItems: "center", gap: 14,
    padding: "9px 28px", borderBottom: "1px solid #efe3c8", background: "#faf5e6",
    fontSize: 12,
  },
  bannerBroken: { color: "#c01818", fontWeight: 600, display: "flex", alignItems: "center", gap: 6, whiteSpace: "nowrap" },
  bannerUpdate: { color: "#8a6400", fontWeight: 600, display: "flex", alignItems: "center", gap: 6, whiteSpace: "nowrap" },
  bannerBtn: (primary) => ({
    fontSize: 11.5, fontWeight: 600, padding: "4px 11px", borderRadius: 5, cursor: "pointer",
    color: primary ? "#fff" : "#5a4a14",
    background: primary ? "#111" : "transparent",
    border: primary ? "1px solid #111" : "1px solid #cdb878",
  }),

  // ── 表格 ─────────────────────────────────────────────
  tdMeta: { color: "#7c7869", fontSize: 11.5 },
  disclosure: { display: "inline-flex", alignItems: "center", justifyContent: "center", width: 16, height: 16, marginRight: 6, fontSize: 9, color: "#444", fontFamily: "ui-monospace, monospace", verticalAlign: "middle" },
  childIndent: { display: "inline-block", color: "#cdc8b9", fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace", fontSize: 12, marginRight: 8, userSelect: "none" },
  updateBadge: {
    display: "inline-block", marginLeft: 6, fontSize: 10, fontWeight: 700,
    fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace",
    color: "#8a6400", background: "#f6ecc8", border: "1px solid #e0cb84",
    borderRadius: 3, padding: "1px 5px", cursor: "pointer", whiteSpace: "nowrap",
  },
  rowAction: {
    display: "inline-flex", alignItems: "center", justifyContent: "center",
    width: 22, height: 22, borderRadius: 5, cursor: "pointer",
    color: "#9a9684", fontSize: 12, border: "1px solid transparent",
  },

  typeTag: (t) => {
    const map = {
      Skill: { c: "#5a4a14", b: "#c9b478", bg: "transparent" },
      Agent: { c: "#1d3c63", b: "#7faacd", bg: "transparent" },
      MCP:   { c: "#3c1d5a", b: "#a98cc9", bg: "transparent" },
      CLI:   { c: "#1a4d33", b: "#74b291", bg: "transparent" },
      Bundle:{ c: "#fff",    b: "#111",    bg: "#111" },
    }[t] || { c: "#666", b: "#d8d5cb", bg: "transparent" };
    return {
      display: "inline-block", fontSize: 9.5, fontWeight: 700, letterSpacing: "0.06em",
      textTransform: "uppercase", padding: "2px 6px", borderRadius: 3,
      color: map.c, background: map.bg, border: `1px solid ${map.b}`,
      lineHeight: 1.4, minWidth: 50, textAlign: "center",
    };
  },

  cell: (status) => {
    const map = {
      on:     { c: "#1f4ed8", weight: 700 },
      off:    { c: "#cdc8b9", weight: 400 },
      stub:   { c: "#b88300", weight: 700 },
      broken: { c: "#c01818", weight: 700 },
    }[status] || { c: "#ccc", weight: 400 };
    return { fontSize: 14, color: map.c, fontWeight: map.weight, lineHeight: 1, fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace" };
  },
  cellHit: { display: "inline-flex", alignItems: "center", justifyContent: "center", width: 28, height: 24, borderRadius: 5, cursor: "pointer" },

  frac: { display: "inline-flex", flexDirection: "column", alignItems: "center", gap: 3, lineHeight: 1 },
  fracText: { fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace", fontSize: 11, fontWeight: 700, fontVariantNumeric: "tabular-nums" },
  fracBar: { width: 36, height: 3, background: "#e6e2d4", borderRadius: 1, overflow: "hidden", display: "flex" },
  fracSeg: (color, w) => ({ background: color, width: `${w}%`, height: "100%" }),

  // ── toast ────────────────────────────────────────────
  toast: {
    position: "absolute", left: "50%", bottom: 44, transform: "translateX(-50%)",
    background: "#111", color: "#fff", fontSize: 12, fontWeight: 500,
    padding: "8px 16px", borderRadius: 7, boxShadow: "0 8px 24px rgba(0,0,0,0.25)",
    zIndex: 60, whiteSpace: "nowrap", letterSpacing: "-0.005em",
  },
};

function PsMark() {
  return (
    <svg width="18" height="18" viewBox="0 0 18 18" fill="none" style={{ display: "block", flexShrink: 0 }}>
      <rect width="18" height="18" rx="5" fill="#111"></rect>
      <circle cx="6.4" cy="6.4" r="1.9" stroke="#fff" strokeWidth="1.3"></circle>
      <circle cx="11.6" cy="11.6" r="1.9" stroke="#fff" strokeWidth="1.3"></circle>
      <path d="M7.9 7.9l2.2 2.2" stroke="#fff" strokeWidth="1.3" strokeLinecap="round"></path>
    </svg>
  );
}

function PsCell({ s, onClick, title }) {
  const sym = { on: "●", off: "—", stub: "◐", broken: "✕" }[s];
  return (
    <span
      style={{ ...psStyles.cellHit, ...(onClick ? {} : { cursor: "default" }) }}
      title={title}
      onClick={onClick}
      onMouseEnter={e => { if (onClick) e.currentTarget.style.background = "rgba(0,0,0,0.05)"; }}
      onMouseLeave={e => { e.currentTarget.style.background = "transparent"; }}
    >
      <span style={psStyles.cell(s)}>{sym}</span>
    </span>
  );
}

// 套装聚合单元格："5/8" + 迷你覆盖条
function PsFraction({ agg }) {
  const { total, on = 0, stub = 0, broken = 0, off = 0 } = agg;
  const pct = (n) => (n / total) * 100;
  const color = on === total ? "#1f4ed8" : (on === 0 && stub === 0 ? "#888" : "#b88300");
  return (
    <div style={psStyles.frac}>
      <span style={{ ...psStyles.fracText, color }}>{on}/{total}</span>
      <div style={psStyles.fracBar}>
        {on > 0 && <div style={psStyles.fracSeg("#1f4ed8", pct(on))}></div>}
        {stub > 0 && <div style={psStyles.fracSeg("#e1a51a", pct(stub))}></div>}
        {broken > 0 && <div style={psStyles.fracSeg("#c01818", pct(broken))}></div>}
        {off > 0 && <div style={psStyles.fracSeg("#e6e2d4", pct(off))}></div>}
      </div>
    </div>
  );
}

function PsTitlebar({ onSettings, onBrand, sync = true }) {
  const s = psStyles;
  return (
    <div style={s.titlebar}>
      <div style={s.lights}>
        <div style={s.light("#ff5f57")}></div>
        <div style={s.light("#febc2e")}></div>
        <div style={s.light("#28c840")}></div>
      </div>
      <div style={{ display: "flex", alignItems: "center", gap: 6, cursor: "pointer" }} onClick={onBrand}>
        <PsMark />
        <div style={s.titleLabel}>Popskill</div>
      </div>
      <div style={s.spacer}></div>
      {sync
        ? <div style={s.syncChip}><span style={s.syncDot}></span>已同步</div>
        : <div style={{ ...s.syncChip, color: "#9a9684", border: "1px solid #e2dfd3", background: "#fafaf8" }}><span style={{ ...s.syncDot, background: "#c4bfb0" }}></span>未连接</div>}
      <div style={{ ...s.kbd, padding: "2px 8px", cursor: "pointer" }} title="设置" onClick={onSettings}>⚙</div>
    </div>
  );
}

function PsStatusbar({ stats, empty, onOpenEditor }) {
  const s = psStyles;
  if (empty) {
    return (
      <div style={s.statusbar}>
        <span style={s.sbMono}>~/.agents</span>
        <span style={s.sbDim}>·</span>
        <span>store 为空</span>
        <span style={s.spacer}></span>
        <span style={{ ...s.syncChipSm, color: "#9a9684" }}><span style={{ ...s.syncDot, background: "#c4bfb0" }}></span>未连接同步</span>
        <span style={s.sbDim}>·</span>
        <span style={s.sbMono}>popskill v0.10.0</span>
      </div>
    );
  }
  return (
    <div style={s.statusbar}>
      <span style={s.sbMono}>~/.agents</span>
      <span style={{ ...s.sbLink, fontSize: 11 }} title="在编辑器中打开 store" onClick={onOpenEditor}>↗ 在编辑器中打开</span>
      <span style={s.sbDim}>·</span>
      <span style={s.sbMono}>{stats.symlinks} symlinks</span>
      <span style={s.sbDim}>·</span>
      <span style={stats.broken > 0 ? { color: "#c01818", fontWeight: 600 } : {}}>{stats.broken} 断链</span>
      <span style={s.sbDim}>/</span>
      <span>{stats.stubs} 占位</span>
      <span style={s.spacer}></span>
      <span style={s.syncChipSm}><span style={s.syncDot}></span>同步于 2 分钟前</span>
      <span style={s.sbDim}>·</span>
      <span style={s.sbMono}>popskill v0.10.0</span>
    </div>
  );
}

function PsToast({ msg }) {
  return <div style={psStyles.toast}>{msg}</div>;
}

// 搜索命中高亮
function psHighlight(text, q) {
  if (!q) return text;
  const t = String(text);
  const idx = t.toLowerCase().indexOf(q);
  if (idx < 0) return t;
  return (
    <React.Fragment>
      {t.slice(0, idx)}
      <mark style={{ background: "#fde68a", color: "#111", borderRadius: 2, padding: "0 1px" }}>{t.slice(idx, idx + q.length)}</mark>
      {t.slice(idx + q.length)}
    </React.Fragment>
  );
}

function psTreeGlyph(isLast) { return isLast ? "└─" : "├─"; }

Object.assign(window, { psStyles, PsMark, PsCell, PsFraction, PsTitlebar, PsStatusbar, PsToast, psHighlight, psTreeGlyph });
