// popskill-app.jsx — 状态容器 + 缩放外壳
// 全部应用状态（entries / tools）住在这里；PsMain 与两个弹层只接收数据和动作。

function PsFitStage({ children }) {
  const { useState, useEffect } = React;
  const [scale, setScale] = useState(1);
  useEffect(() => {
    const fit = () => {
      const m = 40;
      setScale(Math.min((window.innerWidth - m) / 1280, (window.innerHeight - m) / 820, 1));
    };
    fit();
    window.addEventListener("resize", fit);
    return () => window.removeEventListener("resize", fit);
  }, []);
  return (
    <div style={{ position: "fixed", inset: 0, background: "#d9d7d0", display: "flex", alignItems: "center", justifyContent: "center", overflow: "hidden" }}>
      <div style={{ width: 1280, height: 820, transform: `scale(${scale})`, transformOrigin: "center center", position: "relative", flexShrink: 0 }}>
        {children}
      </div>
    </div>
  );
}

// 演示用 Tweaks（工具栏开启 Tweaks 后可见，不属于产品 UI）
const PS_TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "emptyStore": false,
  "expandBundles": false
}/*EDITMODE-END*/;

function PopskillApp() {
  const { useState, useRef, useEffect, useCallback } = React;
  const [db, setDb] = useState(makeInitialState);
  const [sheet, setSheet] = useState(null);      // null | "add" | "settings"
  const [toast, setToast] = useState(null);
  const [flashId, setFlashId] = useState(null);
  const winRef = useRef(null);
  const toastTimer = useRef(null);
  const [tw, setTweak] = useTweaks(PS_TWEAK_DEFAULTS);
  const dbView = tw.emptyStore ? { ...db, entries: [] } : db;

  const say = useCallback((msg) => {
    setToast(msg);
    clearTimeout(toastTimer.current);
    toastTimer.current = setTimeout(() => setToast(null), 2600);
  }, []);

  // esc 关闭弹层
  useEffect(() => {
    const h = (e) => { if (e.key === "Escape") setSheet(null); };
    window.addEventListener("keydown", h);
    return () => window.removeEventListener("keydown", h);
  }, []);

  // ── 能力级变更 ──────────────────────────────────────
  const mutateCap = (capId, fn) => setDb(d => ({
    ...d,
    entries: d.entries.map(e =>
      psIsBundle(e)
        ? { ...e, children: e.children.map(c => c.id === capId ? fn({ ...c }) : c) }
        : (e.id === capId ? fn({ ...e }) : e)
    ),
  }));

  const onToggle = (capId, tool) => mutateCap(capId, c => {
    const next = c[tool] === "on" ? "off" : "on";
    say(next === "on" ? `已链接 ${c.name} → ${tool === "claude" ? "Claude Code" : "Codex CLI"}` : `已断开 ${c.name} 在 ${tool === "claude" ? "Claude Code" : "Codex CLI"} 侧的链接`);
    return { ...c, [tool]: next };
  });

  const onResolve = (capId, tool, status, msg) => {
    mutateCap(capId, c => ({ ...c, [tool]: status, brokenCause: undefined }));
    if (msg) say(msg);
  };

  // ── 源级变更 ────────────────────────────────────────
  const upgradeEntry = (e) => ({
    ...e,
    version: e.latest, latest: undefined,
    brokenCause: undefined,
    ...(e.claude === "broken" ? { claude: "on" } : {}),
    ...(e.codex === "broken" ? { codex: "on" } : {}),
    ...(psIsBundle(e) ? {
      children: e.children.map(c => ({
        ...c, brokenCause: undefined,
        claude: c.claude === "broken" ? "on" : c.claude,
        codex: c.codex === "broken" ? "on" : c.codex,
      })),
    } : {}),
  });

  const onApplyUpdate = (entryId, msg) => {
    setDb(d => {
      const e = d.entries.find(x => x.id === entryId);
      if (!e || !e.latest) return d;
      if (!msg) say(`已更新 ${e.name} → ${e.latest}，symlink 已重链`);
      return { ...d, entries: d.entries.map(x => x.id === entryId ? upgradeEntry(x) : x) };
    });
    if (msg) say(msg);
  };

  const onUpdateAll = () => {
    setDb(d => {
      const n = psUpdates(d.entries).length;
      say(`已更新 ${n} 个源，全部 symlink 已重链`);
      return { ...d, entries: d.entries.map(e => (e.latest && e.latest !== e.version) ? upgradeEntry(e) : e) };
    });
  };

  // 全部修复：对每个问题执行其推荐方案（有新版 → 更新并修复；否则重链本地版本）
  const onFixAll = () => {
    setDb(d => {
      const n = psIssues(d.entries).length;
      say(`已修复 ${n} 个链接问题`);
      return {
        ...d,
        entries: d.entries.map(e => {
          const fixCap = (c) => ({
            ...c, brokenCause: undefined,
            claude: c.claude === "broken" ? "on" : c.claude,
            codex: c.codex === "broken" ? "on" : c.codex,
          });
          const hasBroken = psIsBundle(e)
            ? e.children.some(c => c.claude === "broken" || c.codex === "broken")
            : (e.claude === "broken" || e.codex === "broken");
          if (!hasBroken) return e;
          // 推荐方案：有新版 → 更新并修复（upgradeEntry 同时重链 broken）；否则重链本地版本
          return (e.latest && e.latest !== e.version)
            ? upgradeEntry(e)
            : (psIsBundle(e) ? { ...e, children: e.children.map(fixCap) } : fixCap(e));
        }),
      };
    });
  };

  const onRemoveEntry = (entryId) => {
    setDb(d => {
      const e = d.entries.find(x => x.id === entryId);
      if (e) say(`已移除 ${e.name}，store 副本与全部 symlink 已清理`);
      return { ...d, entries: d.entries.filter(x => x.id !== entryId) };
    });
  };

  const onToggleAuto = (entryId) => setDb(d => ({ ...d, entries: d.entries.map(e => e.id === entryId ? { ...e, autoUpdate: !e.autoUpdate } : e) }));
  const onToggleDefault = (toolId) => setDb(d => ({ ...d, tools: d.tools.map(t => t.id === toolId ? { ...t, defaultTarget: !t.defaultTarget } : t) }));

  // ── 安装（添加弹层确认）─────────────────────────────
  const onInstall = (plan, targets) => {
    const cap = {
      id: `${plan.name}-${Date.now()}`,
      name: plan.name, type: plan.type, desc: plan.desc,
      version: plan.version, author: plan.author, tokens: plan.tokens,
      claude: targets.claude ? "on" : "off",
      codex: targets.codex ? "on" : "off",
      sourceUrl: plan.url, autoUpdate: false,
    };
    setDb(d => ({ ...d, entries: [cap, ...d.entries] }));
    setSheet(null);
    if (tw.emptyStore) setTweak("emptyStore", false); // 演示空态下安装 → 自动回到有内容态
    const n = Object.values(targets).filter(Boolean).length;
    say(n > 0 ? `已安装 ${plan.name} 并链接到 ${n} 个工具` : `已保存 ${plan.name} 到 store（未链接）`);
    setFlashId(cap.id);
    setTimeout(() => setFlashId(null), 1800);
  };

  const onOpenEditor = (name) => say(`已在编辑器中打开 ~/.agents/…/${name}`);
  const onScanLocal = () => say("扫描完成：未发现可收录的本地能力");

  const stats = psStats(dbView.entries);

  return (
    <PsFitStage>
      <div ref={winRef} style={psStyles.win} data-screen-label="Popskill 主窗口">
        <PsTitlebar onSettings={() => setSheet("settings")} onBrand={() => setSheet(null)} sync={!tw.emptyStore} />
        <PsMain
          db={dbView} winRef={winRef} flashId={flashId} expandAll={tw.expandBundles}
          onToggle={onToggle} onResolve={onResolve}
          onApplyUpdate={onApplyUpdate} onFixAll={onFixAll} onUpdateAll={onUpdateAll}
          onOpenAdd={() => setSheet("add")} onRemoveEntry={onRemoveEntry}
          onOpenEditor={onOpenEditor} onScanLocal={onScanLocal}
        />
        <PsStatusbar stats={stats} empty={tw.emptyStore} onOpenEditor={() => onOpenEditor("")} />
        {sheet === "add" && <PsAddSheet tools={db.tools} onClose={() => setSheet(null)} onInstall={onInstall} />}
        {sheet === "settings" && (
          <PsSettingsSheet db={dbView} onClose={() => setSheet(null)}
            onToggleAuto={onToggleAuto} onRemoveEntry={onRemoveEntry}
            onApplyUpdate={onApplyUpdate} onToggleDefault={onToggleDefault} onOpenEditor={onOpenEditor}
            onOpenAdd={() => setSheet("add")} say={say} />
        )}
        {toast && <PsToast msg={toast} />}
        <TweaksPanel>
          <TweakSection label="演示" />
          <TweakToggle label="空 store 态（首次启动）" value={tw.emptyStore} onChange={(v) => setTweak("emptyStore", v)} />
          <TweakToggle label="展开全部套装" value={tw.expandBundles} onChange={(v) => setTweak("expandBundles", v)} />
        </TweaksPanel>
      </div>
    </PsFitStage>
  );
}

Object.assign(window, { PopskillApp, PsFitStage });
