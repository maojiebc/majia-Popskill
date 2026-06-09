// popskill-sheets.jsx — 两个覆盖层：添加（粘贴 URL → 安装计划）与设置
// 源中心被砍后，「添加」收敛为这一个弹层；设置承接源管理（已添加的源 + 工具 + store）。

const psSheetStyles = {
  overlay: { position: "absolute", inset: 0, background: "rgba(24,20,12,0.34)", zIndex: 50, display: "flex", alignItems: "center", justifyContent: "center" },
  card: { width: 560, maxHeight: 680, background: "#fafaf8", borderRadius: 12, border: "1px solid #dcd9cf", boxShadow: "0 24px 64px rgba(0,0,0,0.30)", display: "flex", flexDirection: "column", overflow: "hidden", fontFamily: psStyles.win.fontFamily },
  head: { padding: "16px 20px 13px", borderBottom: "1px solid #e8e6df", background: "#f4f2ec" },
  title: { fontSize: 15.5, fontWeight: 700, letterSpacing: "-0.02em", margin: 0 },
  sub: { fontSize: 11.5, color: "#7c7869", margin: "4px 0 0", lineHeight: 1.5 },
  body: { padding: "16px 20px", overflow: "auto", flex: 1 },
  foot: { padding: "12px 20px", borderTop: "1px solid #e8e6df", background: "#f4f2ec", display: "flex", alignItems: "center", gap: 8 },
  label: { fontSize: 10.5, fontWeight: 700, letterSpacing: "0.06em", textTransform: "uppercase", color: "#9a9684", marginBottom: 6 },
  input: { width: "100%", boxSizing: "border-box", height: 34, padding: "0 11px", borderRadius: 7, border: "1px solid #dcd9cf", background: "#fff", fontSize: 12.5, color: "#111", outline: "none", fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace" },
  exChip: { fontSize: 10.5, fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace", color: "#5e5a4e", padding: "3px 8px", border: "1px solid #e2dfd3", borderRadius: 999, background: "#fff", cursor: "pointer", whiteSpace: "nowrap" },
  btn: (primary, disabled) => ({
    height: 30, padding: "0 14px", borderRadius: 7, display: "inline-flex", alignItems: "center", gap: 6,
    fontSize: 12.5, fontWeight: 600, letterSpacing: "-0.005em", whiteSpace: "nowrap",
    cursor: disabled ? "default" : "pointer",
    color: primary ? "#fff" : "#444",
    background: primary ? (disabled ? "#b3aea0" : "#111") : "transparent",
    border: primary ? "1px solid transparent" : "1px solid #d8d5cb",
  }),
  mono: { fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace" },
  term: { background: "#16140f", borderRadius: 8, padding: "12px 14px", fontFamily: "ui-monospace, SFMono-Regular, Menlo, monospace", fontSize: 11, lineHeight: 1.8, color: "#c9c4b2", overflow: "auto", whiteSpace: "pre" },
  kindTag: { display: "inline-block", fontSize: 9.5, fontWeight: 700, letterSpacing: "0.06em", textTransform: "uppercase", padding: "2px 7px", borderRadius: 3, border: "1px solid #d8d5cb", color: "#5e5a4e", background: "#fff" },
  section: { marginBottom: 22 },
  row: { display: "flex", alignItems: "center", gap: 10, padding: "8px 10px", borderRadius: 7, border: "1px solid #e8e6df", background: "#fff", marginBottom: 6, minWidth: 0 },
  switchOuter: (on) => ({ width: 30, height: 17, borderRadius: 999, background: on ? "#1f4ed8" : "#d8d5cb", position: "relative", cursor: "pointer", flexShrink: 0, transition: "background 0.15s" }),
  switchKnob: (on) => ({ position: "absolute", top: 2, left: on ? 15 : 2, width: 13, height: 13, borderRadius: "50%", background: "#fff", boxShadow: "0 1px 2px rgba(0,0,0,0.2)", transition: "left 0.15s" }),
};

function PsSwitch({ on, onChange, title }) {
  return (
    <div style={psSheetStyles.switchOuter(on)} title={title} onClick={onChange}>
      <div style={psSheetStyles.switchKnob(on)}></div>
    </div>
  );
}

// URL → 安装计划解析（原型：确定性假数据）
function psParseSource(url) {
  const u = url.trim();
  const kind = psSourceKind(u);
  let base = (kind === "npm" ? u.slice(4) : u).split("/").filter(Boolean).pop() || "new-skill";
  base = base.replace(/[^a-zA-Z0-9-_.]/g, "") || "new-skill";
  const author = kind === "github" ? (u.split("/").filter(Boolean)[1] || "unknown")
               : kind === "npm" ? (u.includes("@") ? u.slice(4).split("/")[0] : "npm")
               : "local";
  return { url: u, kind, name: base, author, version: "1.0.0", type: "Skill", tokens: 9200, desc: "从源 manifest 读取的描述" };
}

// ── 添加弹层：粘贴 URL → 安装计划 → 安装并链接 ───────────
function PsAddSheet({ tools, onClose, onInstall }) {
  const { useState } = React;
  const s = psSheetStyles;
  const [url, setUrl] = useState("");
  const [plan, setPlan] = useState(null);
  const [targets, setTargets] = useState(() => Object.fromEntries(tools.map(t => [t.id, t.defaultTarget])));
  const examples = ["github.com/dotey/prompt-engineering", "npm:@upstash/context7-mcp", "~/work/my-skills/ppt-generator"];
  const nTargets = Object.values(targets).filter(Boolean).length;
  const kindDir = { Skill: "skills", Agent: "agents", MCP: "mcp", CLI: "bin" };

  return (
    <div style={s.overlay} onClick={onClose}>
      <div data-screen-label="添加弹层" style={{ ...s.card, width: 520 }} onClick={e => e.stopPropagation()}>
        <div style={s.head}>
          <h2 style={s.title}>添加能力</h2>
          <p style={s.sub}>粘贴 GitHub 仓库 / npm 包 / 本地路径 — 安装一次进 store，再选择挂载到哪些工具。</p>
        </div>

        {!plan ? (
          <React.Fragment>
            <div style={s.body}>
              <div style={s.label}>来源 URL</div>
              <input autoFocus style={s.input} value={url} placeholder="github.com/owner/repo · npm:pkg · ~/path"
                onChange={e => setUrl(e.target.value)}
                onKeyDown={e => { if (e.key === "Enter" && url.trim()) setPlan(psParseSource(url)); }} />
              <div style={{ display: "flex", gap: 6, marginTop: 10, flexWrap: "wrap" }}>
                {examples.map(x => <span key={x} style={s.exChip} onClick={() => setUrl(x)}>{x}</span>)}
              </div>
            </div>
            <div style={s.foot}>
              <span style={psStyles.spacer}></span>
              <div style={s.btn(false)} onClick={onClose}>取消</div>
              <div style={s.btn(true, !url.trim())} onClick={() => url.trim() && setPlan(psParseSource(url))}>解析 →</div>
            </div>
          </React.Fragment>
        ) : (
          <React.Fragment>
            <div style={s.body}>
              {/* 解析结果 */}
              <div style={s.section}>
                <div style={s.label}>来源</div>
                <div style={s.row}>
                  <span style={s.kindTag}>{plan.kind}</span>
                  <span style={{ ...s.mono, fontSize: 11.5, color: "#111", flex: 1, minWidth: 0, overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{plan.url}</span>
                  <span style={{ fontSize: 11, color: "#7c7869", fontVariantNumeric: "tabular-nums" }}>v{plan.version}</span>
                </div>
              </div>
              <div style={s.section}>
                <div style={s.label}>提供 1 项</div>
                <div style={s.row}>
                  <span style={{ fontSize: 12.5, fontWeight: 600, whiteSpace: "nowrap" }}>{plan.name}</span>
                  <span style={psStyles.typeTag(plan.type)}>{plan.type}</span>
                  <span style={psStyles.spacer}></span>
                  <span style={{ fontSize: 11, color: "#9a9684" }}>{(plan.tokens / 1000).toFixed(1)}k tokens</span>
                </div>
              </div>
              {/* 挂载目标 */}
              <div style={s.section}>
                <div style={s.label}>挂载到</div>
                {tools.map(t => (
                  <div key={t.id} style={s.row}>
                    <span style={{ fontSize: 12.5, fontWeight: 600, whiteSpace: "nowrap" }}>{t.name}</span>
                    <span style={{ ...s.mono, fontSize: 10.5, color: "#9a9684" }}>{t.root}{kindDir[plan.type]}/</span>
                    <span style={psStyles.spacer}></span>
                    <PsSwitch on={!!targets[t.id]} onChange={() => setTargets(prev => ({ ...prev, [t.id]: !prev[t.id] }))} />
                  </div>
                ))}
              </div>
              {/* 将写入 */}
              <div>
                <div style={s.label}>将写入</div>
                <div style={s.term}>
{`~/.agents/${kindDir[plan.type]}/${plan.name}-${plan.version}/`}
{tools.filter(t => targets[t.id]).map(t => `\nln -s ~/.agents/${kindDir[plan.type]}/${plan.name}-${plan.version} ${t.root}${kindDir[plan.type]}/${plan.name}`).join("")}
                </div>
              </div>
            </div>
            <div style={s.foot}>
              <div style={s.btn(false)} onClick={() => setPlan(null)}>← 返回</div>
              <span style={psStyles.spacer}></span>
              <div style={s.btn(false)} onClick={onClose}>取消</div>
              <div style={s.btn(true)} onClick={() => onInstall(plan, targets)}>
                {nTargets > 0 ? `安装并链接 (${nTargets})` : "仅保存到 store"}
              </div>
            </div>
          </React.Fragment>
        )}
      </div>
    </div>
  );
}

// ── 设置弹层：已添加的源 / 工具 / Store 与同步 / 安装默认 ─
function PsSettingsSheet({ db, onClose, onToggleAuto, onRemoveEntry, onApplyUpdate, onToggleDefault, onOpenEditor, onOpenAdd, say }) {
  const s = psSheetStyles;
  const entries = db.entries;
  return (
    <div style={s.overlay} onClick={onClose}>
      <div data-screen-label="设置弹层" style={s.card} onClick={e => e.stopPropagation()}>
        <div style={{ ...s.head, display: "flex", alignItems: "flex-start" }}>
          <div style={{ flex: 1 }}>
            <h2 style={s.title}>设置</h2>
            <p style={s.sub}>源、工具与 store — 全部配置都在这一页。</p>
          </div>
          <div style={{ ...psStyles.kbd, cursor: "pointer" }} onClick={onClose}>esc</div>
        </div>
        <div style={s.body}>

          <div style={s.section}>
            <div style={s.label}>已添加的源（{entries.length}）</div>
            {entries.map(e => {
              const hasUpdate = e.latest && e.latest !== e.version;
              const n = psIsBundle(e) ? e.children.length : 1;
              return (
                <div key={e.id} style={s.row}>
                  <span style={s.kindTag}>{psSourceKind(e.sourceUrl)}</span>
                  <div style={{ flex: 1, minWidth: 0 }}>
                    <div style={{ ...s.mono, fontSize: 11.5, color: "#111", overflow: "hidden", textOverflow: "ellipsis", whiteSpace: "nowrap" }}>{e.sourceUrl}</div>
                    <div style={{ fontSize: 10.5, color: "#9a9684", marginTop: 1 }}>提供 {e.name}{n > 1 ? ` 等 ${n} 项` : ""} · v{e.version}</div>
                  </div>
                  {hasUpdate && <span style={psStyles.updateBadge} title={`更新到 ${e.latest}`} onClick={() => onApplyUpdate(e.id)}>↑ {e.latest}</span>}
                  <PsSwitch on={!!e.autoUpdate} title="自动更新" onChange={() => onToggleAuto(e.id)} />
                  <span style={{ ...psStyles.rowAction, visibility: "visible" }} title="移除该源（含其能力）"
                    onClick={() => onRemoveEntry(e.id)}
                    onMouseEnter={ev => { ev.currentTarget.style.color = "#c01818"; }}
                    onMouseLeave={ev => { ev.currentTarget.style.color = "#9a9684"; }}>✕</span>
                </div>
              );
            })}
            <div style={{ display: "flex", alignItems: "center", gap: 8, marginTop: 6 }}>
              <div style={{ ...s.btn(false), fontSize: 11.5, height: 26 }} onClick={onOpenAdd}>+ 粘贴 URL 添加</div>
              <span style={{ fontSize: 10.5, color: "#9a9684" }}>开关 = 自动更新。移除源会同时卸载它提供的能力与 symlink。</span>
            </div>
          </div>

          <div style={s.section}>
            <div style={s.label}>工具（挂载目标）</div>
            {db.tools.map(t => (
              <div key={t.id} style={s.row}>
                <span style={{ width: 7, height: 7, borderRadius: "50%", background: t.connected ? "#1a9a4e" : "#c4bfb0", flexShrink: 0 }}></span>
                <span style={{ fontSize: 12.5, fontWeight: 600, whiteSpace: "nowrap" }}>{t.name}</span>
                <span style={{ ...s.mono, fontSize: 10.5, color: "#9a9684" }}>{t.root}</span>
                <span style={psStyles.spacer}></span>
                <span style={{ fontSize: 10.5, color: "#9a9684" }}>新安装默认挂载</span>
                <PsSwitch on={!!t.defaultTarget} onChange={() => onToggleDefault(t.id)} />
              </div>
            ))}
            <div style={{ ...s.btn(false), marginTop: 2, fontSize: 11.5, height: 26 }} onClick={() => say && say("原型未实现：添加自定义工具（任意支持文件系统 skill 的 CLI）")}>+ 添加工具…</div>
          </div>

          <div style={s.section}>
            <div style={s.label}>Store 与同步</div>
            <div style={s.row}>
              <span style={{ ...s.mono, fontSize: 11.5, color: "#111" }}>~/.agents</span>
              <span style={psStyles.spacer}></span>
              <div style={{ ...s.btn(false), height: 24, fontSize: 11 }} onClick={() => onOpenEditor("store")}>↗ 在编辑器中打开</div>
            </div>
            <div style={s.row}>
              <span style={{ fontSize: 12.5 }}>同步后端</span>
              <span style={psStyles.spacer}></span>
              <span style={{ fontSize: 11.5, color: "#5a7a5f", fontWeight: 600 }}>iCloud Drive · 已同步</span>
            </div>
            <div style={{ fontSize: 10.5, color: "#9a9684", marginTop: 4 }}>store 在设备间同步；symlink 是各机本地状态，不参与同步。</div>
          </div>

          <div style={{ ...s.section, marginBottom: 4 }}>
            <div style={s.label}>关于</div>
            <div style={{ fontSize: 11.5, color: "#7c7869" }}>popskill v0.10.0 · store 482 MB · MIT</div>
          </div>

        </div>
      </div>
    </div>
  );
}

Object.assign(window, { PsAddSheet, PsSettingsSheet, PsSwitch, psParseSource, psSheetStyles });
