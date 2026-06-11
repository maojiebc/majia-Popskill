# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 2.x（最新版） | ✅        |
| < 2.0.0 | ❌（v1.x 已下线）|

## Reporting a vulnerability

**Email**: [m9224@163.com](mailto:m9224@163.com)

Please don't open a public GitHub issue for security bugs — file them privately to the email above. I'll acknowledge within 72 hours and aim to ship a patch within 14 days for critical issues.

## Threat model

Popskill runs **100% locally** on the user's Mac. It does **NOT**:

- Make outbound network requests, except: (a) Sparkle checking for app updates, (b) `git clone` / `git ls-remote` of the upstream repos of **your own skills** when you run a skill update check
- Collect usage analytics or telemetry
- Read or write outside the user's home directory — with one exception: GitHub installs/update checks shallow-clone into the **system temporary directory** (`$TMPDIR`), and the clone is deleted when the operation finishes or fails

Paths Popskill reads / writes:

| Path | Purpose |
|---|---|
| `~/.agents/skills/` (+ `agents/ mcp/ bin/`) | Store (SSOT) — the real skill folders |
| `~/.agents/.popskill.json` | App metadata: sources / auto-update flags |
| `~/.agents/.trash/` | Recycle bin — anything replaced or removed lands here (200 kept, FIFO) |
| `~/.claude/skills/`, `~/.codex/skills/` | Per-tool symlinks into the store |
| `~/.agents/.skill-lock.json` | Read-only — provenance from the `npx skills` ecosystem |
| `~/Library/Caches/Sparkle/` | Sparkle's update download cache |
| `$TMPDIR/popskill-stage-*` | Transient shallow clones during GitHub install / update check (removed afterwards) |

Three hard safety rules, enforced by unit tests: only symlinks are ever deleted; real directories always go to `~/.agents/.trash/`; store directories are never touched by enable/disable toggles.

## Sparkle auto-update integrity

Every release DMG is signed with an EdDSA private key. The running app verifies download integrity against the public key baked into Info.plist:

```
SUPublicEDKey = h7HOqj21MlKe5UJFFa9GKBmV6MtdlcDSeJa9rmAguq8=
```

If a Popskill update is offered that doesn't verify against this key, Sparkle refuses it. Even a GitHub Releases compromise wouldn't let an attacker push a forged update — they'd need the matching private key (stored in my Mac Keychain, never committed).

If you ever see a Popskill update dialog where the fingerprint doesn't match the above, refuse the update and email [m9224@163.com](mailto:m9224@163.com) immediately.

## Code signing

The Mac app is signed with **Developer ID Application: JIE MIAO (8KTT7H3QEH)**, notarized by Apple, and stapled. Verify with:

```bash
codesign --verify --deep --strict --verbose=2 /Applications/Popskill.app
spctl --assess --type execute --verbose /Applications/Popskill.app
xcrun stapler validate /Applications/Popskill.app
```

All three should report success.

## What's NOT in the threat model

Things Popskill explicitly does not defend against:

- An attacker with root or local-user write access to the Mac (they can modify `~/.agents/` or `Sparkle.framework` directly)
- A compromised macOS Keychain
- A malicious skill / agent the user installs themselves — Popskill is a manager, it doesn't audit skill content（update-check traversal does refuse to follow symlinks out of the store, but skill *content* is your responsibility）

## Acknowledgements

Security improvements that came out of community reports will be listed here with credit (with the reporter's permission).
