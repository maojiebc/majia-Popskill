# Popskill — Project Notes for Claude

> 项目快照 — 让任何 Claude Code session 在这个目录下都能 5 秒 catch up。

## 是什么

**Popskill** = Mac 上 AI 能力的统一控制台。Skills × Tools 矩阵，把 Claude Code 和 Codex 的 skill / agent / CLI / MCP 摆成一张表，一键开关 + 链接健康 + iCloud sync + Sparkle 自动更新。

公开 repo：https://github.com/maojiebc/majia-Popskill

## 已发布版本

| 版本 | 日期 | 主线 |
|---|---|---|
| v1.0.0 | 2026-05-16 | 第一次签名 + 公证 DMG |
| v1.0.1 | 2026-05-16 | Sparkle 自动更新接通 |
| v1.0.2 | 2026-05-17 | SSOT 路径修复 + error toast + 30s TTL |
| v1.0.3 | 2026-05-17 | UI tokens + hover state + O(1) update lookup |

## 项目结构

```
popskill/
├── skill-cli/                            Rust sidecar (CC Switch as path dep, zero fork)
├── swift-app/Sources/Popskill/
│   ├── App/PopskillStore.swift           @MainActor @Observable, 单 store
│   ├── Models/                           Skill / MatrixCapability / SkillGrouping
│   ├── Views/                            Matrix / Spotlight / Onboarding / 7 次级 view
│   ├── Design/PopskillColors.swift       named tokens (popSurface / popControlFill / ...)
│   └── Resources/{AppIcon.icns, *.lproj/Localizable.strings}
├── cc-switch/                            submodule, sidecar 依赖
├── docs/
│   ├── appcast.xml                       Sparkle feed (GitHub Pages 服务)
│   ├── release/v{N}.md                   每版 release notes
│   └── screenshots/                      landing page 资源
├── scripts/
│   ├── package-dev-app.sh                .app bundle 组装 (含 Info.plist heredoc + Sparkle 烤入)
│   ├── notarize.sh                       sign + 深度签 Sparkle + notarize + staple
│   ├── package-dmg.sh                    hdiutil DMG
│   ├── sparkle-sign-update.sh            EdDSA 签名 wrapper
│   ├── ci-local.sh                       全 pipeline
│   └── ...
├── README.md / README.en.md              landing-page 形式
├── SECURITY.md / .ota-deny-list.txt
└── build/                                gitignored, 经常 rm
```

## 凭证 / 路径（设了一次终生有效）

| 项 | 值 |
|---|---|
| Apple Team ID | `8KTT7H3QEH` (JIE MIAO) |
| Apple ID | `306186636@qq.com` |
| Codesign identity | `Developer ID Application: JIE MIAO (8KTT7H3QEH)` |
| notarytool keychain profile | `popskill-notarize` |
| Bundle ID | `com.majia.popskill` |
| Sparkle 公钥 (Info.plist) | `h7HOqj21MlKe5UJFFa9GKBmV6MtdlcDSeJa9rmAguq8=` |
| Sparkle 私钥 | macOS Keychain (Sparkle Account) — **务必备份** |
| Developer ID 私钥 | `~/.popskill-signing/app.key` — **务必备份** |
| GitHub Pages | https://maojiebc.github.io/majia-Popskill/ |
| Appcast URL | https://maojiebc.github.io/majia-Popskill/appcast.xml |

## 关键架构事实

- **真实 SSOT** = `~/.cc-switch/skills/`，**不是** `~/.agents/skills/`。`.agents/skills` 是 v0.3 文档里画的迁移目标，sidecar 没动。v1.1.x 计划迁移。
- **store.skills vs store.capabilities** — `skills` 只是 Skill；`capabilities` = skills + localAgents，是矩阵真正消费的数据源。新代码默认用 `capabilities`。
- **store.hasPendingUpdate(for:)** 是 O(1) 用 `updateSkillIDs: Set<String>` cache，不要再写 `store.updates.contains` 扫描。
- **`@MainActor` 标在 PopskillStore 类上**，所有 mutating helpers / extensions / filters 必须显式 `@MainActor`。
- **errorMessage 现在被 RootView 全局 toast 读取**（v1.0.2 之前是写了没人看）。任何 sidecar 调用失败 set 这个就行。
- **refresh TTL = 30s**。Sources / Updates / Backups view 用 `store.refreshXXX(force: Bool)` helper；手动按钮 force=true，自动 .task force=false。

## Release Pipeline（重复一次背下来）

```bash
cd /Users/majia/projects/popskill

# 1. 写 docs/release/v1.0.X.md
# 2. 改 scripts/package-dev-app.sh 默认 fallback (可选)

export POPSKILL_APP_VERSION=1.0.X
export POPSKILL_APP_BUILD=10X
export POPSKILL_DEVELOPER_ID_APPLICATION="Developer ID Application: JIE MIAO (8KTT7H3QEH)"
export POPSKILL_TEAM_ID=8KTT7H3QEH
export POPSKILL_APPLE_ID=306186636@qq.com
export POPSKILL_NOTARY_KEYCHAIN_PROFILE=popskill-notarize
export POPSKILL_DMG_PATH="$PWD/build/Popskill-1.0.X.dmg"

rm -rf build/Popskill.app build/Popskill-notary.zip "$POPSKILL_DMG_PATH"
scripts/package-dev-app.sh                                       # .app
scripts/notarize.sh                                              # sign + notarize + staple
scripts/package-dmg.sh                                           # DMG
codesign --force --sign "$POPSKILL_DEVELOPER_ID_APPLICATION" --timestamp "$POPSKILL_DMG_PATH"
xcrun notarytool submit "$POPSKILL_DMG_PATH" --keychain-profile popskill-notarize --wait
xcrun stapler staple "$POPSKILL_DMG_PATH"

# Sparkle 签 + 拿到 sig + len
scripts/sparkle-sign-update.sh "$POPSKILL_DMG_PATH"
stat -f%z "$POPSKILL_DMG_PATH"

# 手动在 docs/appcast.xml 顶上加一个 <item>（newest first）— 用上面的 sig + len

git add docs/appcast.xml docs/release/v1.0.X.md scripts/package-dev-app.sh
git commit -m "v1.0.X release"
git push origin main
gh release create v1.0.X "$POPSKILL_DMG_PATH" --title "Popskill v1.0.X" --notes-file docs/release/v1.0.X.md --target main
```

整条 pipeline 5-10 分钟，瓶颈是 Apple notary（每次 1-3 min）。

## 已知坑（不要再踩）

1. **PKCS12 import "MAC verification failed"** — OpenSSL 3.x 默认不行,导入 .p12 必须加 `-legacy -keypbe PBE-SHA1-3DES -macalg SHA1`
2. **`security find-identity` 显示 0 valid** — 缺 Developer ID G2 intermediate，`curl https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer | security import -`
3. **Notary Invalid → Sparkle nested binary** — `Sparkle.framework/Versions/B/Updater.app/Contents/MacOS/Updater` 和 `Autoupdate` 必须单独 codesign `--options runtime --timestamp`，**深度优先**，再签外层 framework。`scripts/notarize.sh` 已做。
4. **GitHub Pages 首次 build 1-2 min** — `gh api .../pages/builds/latest` status 看到 "built" 再 curl
5. **磁盘满 / ENOSPC** — `swift-app/.build/` 经常 1.2GB，`skill-cli/target/` 200MB+，`build/` 累计 100MB+。改大代码前用 `rm -rf swift-app/.build/ skill-cli/target/ build/` 留 ≥2GB
6. **v1.0.0 用户没 Sparkle** — 第一次升级必须手动下 v1.0.1+，从 v1.0.1 开始才用 Sparkle
7. **外部 patch 大概率 base 不在 HEAD** — `git apply --3way` 而不是 `git apply --check`

## 测试基线

- `swift test --package-path swift-app` = **88/88** (v1.0.3)
- `cargo test --manifest-path skill-cli/Cargo.toml` = 44/44
- `scripts/ci-local.sh` = 全绿
- 实测机：majia 自己 Mac，59 skill / 71 active toggle / 13 GitHub sources / 189 transcript sessions

## majia-ota-app skill（这次会话沉淀出来的）

- 位置：`~/.claude/skills/majia-ota-app/` (canonical) + 3 镜像
- 伞形：`maojiebc/majia-private-skills/skills/majia-ota-app/`
- 范围：Mac app 发布全链 — 一次性 setup (cert / notary / Sparkle / icon) + 每版 cut + Phase 3 public launch (landing-page README / author block / PII scan / big-launch 渠道)
- 触发：发布 mac app / Sparkle 自动更新 / 签名公证 / appcast 等
- v0.2.0 已经把 Popskill 实战学费（PKCS12 / G2 / Sparkle deep-sign 三大坑）记进 `references/troubleshooting.md`

下次发其他 Mac app 直接 invoke 这个 skill。

## 当前状态（2026-05-17）

- v1.0.3 是 Latest，main 干净，无未推内容
- 累计 commit ~30，从 v0.3 wipe 算起 ~70 个
- README 是 landing page，docs/screenshots/ 6 张实拍
- Sparkle 升级链 + GitHub Pages + GitHub Releases 全通

## 下一步候选（v1.1.x 范围）

按优先级，每条都是独立 sprint：

1. **Matrix Gemini 第三列** — `TargetApp.quickToggleSupported` 已列 .gemini，但 sidecar 只接 Claude / Codex；需要 sidecar 加 .gemini/skills 扫描 + Swift 端动态 ForEach 列头
2. **SSOT 路径迁移 .cc-switch/skills → .agents/skills** — sidecar 要做平滑迁移逻辑（rsync + symlink），Swift 端只要改 ssotPath 字符串
3. **WebDAV sync 真接** — sidecar 复用 cc-switch 已有 webdav 命令；Settings 去 SOON 标签
4. **AgentShield 安全扫描复接** — sidecar `security-scan` 命令已存在，Swift 端要做 UI（应该是矩阵行旁的 badge + 详情）
5. **Hover / 选中态推广到其他 view** — Inspector / Sources / Updates view 还是 v0.3 风格，v1.0.3 的 token 体系可以推广

## 常用命令速查

```bash
# 跑应用看效果
export POPSKILL_CLI=/Users/majia/projects/popskill/skill-cli/target/debug/skill-cli
/Users/majia/projects/popskill/swift-app/.build/debug/Popskill

# 跑特定 view（截图调试）
export POPSKILL_DEFAULT_VIEW=insights         # matrix / sources / updates / backups / idle / insights / health / settings
export POPSKILL_DEFAULT_OVERLAY=spotlight     # 或 onboarding

# 看 sidecar 状态
$POPSKILL_CLI health --json
$POPSKILL_CLI list --json | head -20

# PII 扫描
python3 ~/.claude/skills/majia-ota-app/scripts/audit-mac-app-release.py .

# 更新 GitHub About
~/.claude/skills/majia-ota-app/scripts/update-github-about.sh \
  --repo maojiebc/majia-Popskill --description "..." --homepage "..." --topics "..."
```

## 沟通偏好（来自 user memory）

- 用中文沟通
- 默认产物输出 `~/Downloads/{项目-slug}/`
- 不要做 "summary + emoji 满天飞" 风格；direct + 具体数字
- 大改前先列计划，用户说"做"再开干

---

最后更新：2026-05-17，v1.0.3 发布后
