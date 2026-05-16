# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| 1.0.x   | ✅        |
| < 1.0.0 | ❌        |

## Reporting a vulnerability

**Email**: [m9224@163.com](mailto:m9224@163.com)

Please don't open a public GitHub issue for security bugs — file them privately to the email above. I'll acknowledge within 72 hours and aim to ship a patch within 14 days for critical issues.

## Threat model

Popskill runs **100% locally** on the user's Mac. It does **NOT**:

- Make outbound network requests, except via Sparkle for update checks
- Collect usage analytics or telemetry
- Read or write outside the user's home directory

Paths Popskill reads / writes (all in `$HOME`):

| Path | Purpose |
|---|---|
| `~/.cc-switch/skills/` | SSOT — the real skill files (managed by CC Switch upstream) |
| `~/.claude/skills/`, `~/.codex/skills/`, `~/.agents/skills/` | symlinks to the above per AI-tool root |
| `~/.popskill/backups/` | Snapshot backups created by safe uninstalls |
| `~/.claude/projects/*.jsonl` | Read-only — for token usage analysis |
| `~/Library/Caches/Sparkle/` | Sparkle's update download cache |

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

- An attacker with root or local-user write access to the Mac (they can modify `~/.cc-switch/skills/` or `Sparkle.framework` directly)
- A compromised macOS Keychain
- A malicious skill / agent the user installs themselves — Popskill is a manager, it doesn't audit skill content; pair with the AgentShield scan path (planned for v1.1.x)

## Acknowledgements

Security improvements that came out of community reports will be listed here with credit (with the reporter's permission).
