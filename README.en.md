# Popskill

> **One control surface for AI capabilities on macOS.** Skills × tools matrix for Claude Code and Codex, with one-click toggles, link health, iCloud sync, and token usage insights.

<p align="center">
  <a href="https://github.com/maojiebc/majia-Popskill/releases/latest/download/Popskill-1.0.5.dmg">
    <img src="docs/screenshots/hero.jpg" alt="Popskill capability × tool matrix" width="900">
  </a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-blue?logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/github/v/release/maojiebc/majia-Popskill?color=orange" alt="Latest release">
  <img src="https://img.shields.io/github/downloads/maojiebc/majia-Popskill/total?color=green" alt="Downloads">
  <img src="https://img.shields.io/github/license/maojiebc/majia-Popskill" alt="MIT License">
  <img src="https://img.shields.io/badge/Sparkle-auto--update-purple" alt="Sparkle">
</p>

> [中文 README](./README.md) · English

---

## Install

[**↓ Download Popskill 1.0.5 (17.8 MB, signed + notarized)**](https://github.com/maojiebc/majia-Popskill/releases/latest/download/Popskill-1.0.5.dmg)

Requires macOS 14 (Sonoma) or newer. After first install, Sparkle prompts in-app for future versions — no need to come back here.

The DMG is signed with an Apple Developer ID, notarized, and stapled, so **Gatekeeper opens it cleanly** — no "unidentified developer" warning.

---

## Why this exists

I use Claude Code and Codex daily. Both keep skills in their own roots (`~/.claude/skills/` and `~/.codex/skills/`). Sharing a skill between both means manually symlinking, which I keep forgetting.

```text
~/.claude/skills/baoyu-comic/        ← Claude finds it
~/.codex/skills/baoyu-comic/         ← Codex doesn't (until I manually ln -s)
```

The annoying part isn't the symlink itself — it's **not knowing which side has what right now**. Popskill makes that visible: every skill / agent / CLI / MCP lined up against every AI tool in a matrix, one click to toggle.

---

## Screenshots

<table>
<tr>
<td width="50%"><img src="docs/screenshots/matrix.jpg" alt="Capability × tool matrix"></td>
<td width="50%"><img src="docs/screenshots/spotlight.jpg" alt="⌘K Spotlight"></td>
</tr>
<tr>
<td><b>Capability × tool matrix</b> — one row per skill, one column per AI tool, click to toggle</td>
<td><b>⌘K Spotlight</b> — search anywhere; ⌘1 / ⌘2 to toggle Claude / Codex directly on a result</td>
</tr>
<tr>
<td width="50%"><img src="docs/screenshots/insights.jpg" alt="Token usage"></td>
<td width="50%"><img src="docs/screenshots/settings.jpg" alt="Settings + sync"></td>
</tr>
<tr>
<td><b>Token usage</b> — scans ~/.claude/projects locally for total tokens + top 10 capabilities by usage</td>
<td><b>Sync</b> — iCloud Drive or Git remote, cross-Mac auto-sync</td>
</tr>
</table>

---

## Features

- **Capability matrix** — Skill / Agent / CLI / MCP / Package across Claude Code + Codex, one-click toggle. Packages (suites) are first-class rows that expand to show their components
- **⌘K command palette** — search capabilities and run quick actions without leaving the keyboard. Empty-query results ranked by 30-day usage; CJK aliases supported (`baoyu-comic` / `baoyu comic` / `宝玉漫画` all resolve)
- **Link health monitor** — see SSOT real path + per-tool symlink status; broken links surface immediately, with sidebar shortcuts to filter
- **Token usage insights** — local-only scan of ~/.claude/projects/*.jsonl for total tokens + top 10 capabilities. Streaming parser keeps memory at ~50MB even on hundreds of MB of transcripts
- **5-step onboarding wizard** — first launch detects installed tools, scans existing capabilities, helps pick sync
- **iCloud Drive sync** — change config on one Mac, other Macs pick it up on next launch
- **Safe-by-default uninstalls** — every uninstall creates a backup snapshot; idle (60+ days) capabilities surface their own view
- **Sparkle auto-update** — EdDSA-verified updates, fake DMGs rejected

---

## Quickstart

First launch runs the onboarding wizard:

1. **Welcome** — intro to what Popskill does
2. **Detect tools** — looks at your machine for Claude Code, Codex, brew CLIs, npm globals
3. **Scan capabilities** — lists everything already in ~/.agents/skills/, ~/.claude/skills/, ~/.codex/skills/
4. **Storage + sync** — pick iCloud Drive or Git remote for cross-Mac sync
5. **Done** — drops you on the matrix view

If you already have skills installed, you see them immediately; no "configure Popskill first" step.

---

## How it works

```
┌─────────────────────────────────────────┐
│  SwiftUI front-end (this app)           │
│  • Matrix + Inspector                   │
│  • ⌘K Spotlight                         │
│  • Onboarding wizard                    │
└────────────────────┬────────────────────┘
                     │ JSON over stdin/stdout
                     ▼
┌─────────────────────────────────────────┐
│  skill-cli (Rust sidecar)               │
│  • list / toggle / install / uninstall  │
│  • scans ~/.claude / ~/.codex / ~/.agents│
│  • link-health / sync (Git / iCloud)    │
└────────────────────┬────────────────────┘
                     │ git submodule (zero-fork)
                     ▼
┌─────────────────────────────────────────┐
│   CC Switch (upstream skill store)      │
└─────────────────────────────────────────┘
```

Zero-fork dependency on [CC Switch](https://github.com/farion1231/cc-switch) as a git submodule — Popskill reuses upstream skill storage logic and adds UI + cross-tool orchestration.

---

## FAQ

**Why isn't this in the Mac App Store?**
App Store sandbox rules block the symlink management Popskill needs to do. Direct Developer ID distribution lets the app actually work; the trade-off is you download from here instead of the App Store.

**Do you collect any data?**
No. 100% local — no telemetry, no analytics. Token usage insights are computed from `~/.claude/projects/*.jsonl` on your Mac; nothing leaves the machine.

**Is Sparkle auto-update safe?**
Yes. Every DMG is signed with an EdDSA private key (in my Keychain) and the running app verifies with the public key baked into Info.plist (`SUPublicEDKey=h7HOqj21MlKe5UJFFa9GKBmV6MtdlcDSeJa9rmAguq8=`). Even if GitHub Releases were compromised, a forged DMG would fail verification.

**How do I uninstall?**
Drag `/Applications/Popskill.app` to the Trash. To also wipe data, delete `~/.popskill/`. Your actual skills (`~/.cc-switch/skills/`) are yours — Popskill doesn't own them.

**Where is data stored?**
- SSOT (your skills' real files): `~/.cc-switch/skills/`
- Popskill backups: `~/.popskill/backups/`
- Sparkle cache: `~/Library/Caches/Sparkle/`

All within your home directory; no system-level state.

**Windows / Linux support?**
Mac only. Rust sidecar is portable; SwiftUI front-end isn't. If someone wants to port the UI to GTK / Qt, the sidecar IPC protocol is stable.

---

## System requirements

| macOS | Status | Notes |
|---|---|---|
| 26 Tahoe | ✅ | Primary target |
| 14 Sonoma | ✅ | LSMinimumSystemVersion |
| 13 Ventura | ❓ | Not tested; may work |
| 12 Monterey | ❌ | Below minimum |

---

## Releases

See [GitHub Releases](https://github.com/maojiebc/majia-Popskill/releases) for changelogs and signed DMGs.

- [v1.0.5](./docs/release/v1.0.5.md) — Package matrix as first-class rows + Inspector tabs + Spotlight CJK aliases (**Latest**)
- [v1.0.4](./docs/release/v1.0.4.md) — Spotlight/Idle jump fixes + delete confirmation + Insights streaming parser
- [v1.0.3](./docs/release/v1.0.3.md) — UI design tokens + Hover/Selected states + O(1) update lookup
- [v1.0.2](./docs/release/v1.0.2.md) — SSOT path fix + global error toast + 30s refresh TTL
- [v1.0.1](./docs/release/v1.0.1.md) — Sparkle auto-update wired
- [v1.0.0](./docs/release/v1.0.0.md) — first signed + notarized release

---

## Contributing

PRs welcome. Open an issue first for substantial changes.

Bug reports / ideas: [GitHub Issues](https://github.com/maojiebc/majia-Popskill/issues) or email me (see below).

---

## 👤 Author / Contact

**Majia (@maojiebc)** · 超级马甲 (Super Majia)

If this Mac app helps you, find me on any of these channels — happy to chat about field experience, take feature requests, hear bug reports, or trade notes on Mac app development / user operations / AI toolchain integration:

| Channel | Link |
|---|---|
| 📧 Email | [m9224@163.com](mailto:m9224@163.com) |
| 🐙 GitHub | [github.com/maojiebc](https://github.com/maojiebc) |
| 🪝 ClawHub | [clawhub.ai/p/maojiebc](https://clawhub.ai/p/maojiebc) |
| 🐦 X | [@maojiebc](https://x.com/maojiebc) |
| 📕 Xiaohongshu | [Super Majia](https://xhslink.com/m/4fQMJeHHWKC) |
| 📰 WeChat Official Account | **超级马甲** |

> Built from 14 years of user-operations work plus hands-on AI tooling integration on macOS.

---

## Acknowledgements

- [CC Switch](https://github.com/farion1231/cc-switch) — skill storage engine, zero-fork git submodule
- [Sparkle](https://sparkle-project.org/) — auto-update framework
- [@dotey](https://x.com/dotey), [@op7418](https://x.com/op7418), and the broader Claude Skill author community — who made the whole AI Skill ecosystem real

---

## License

[MIT](./LICENSE) · Copyright © 2026 majia
