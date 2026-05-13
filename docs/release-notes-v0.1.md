# Popskill v0.1 Release Notes Draft

Popskill v0.1 is a pre-alpha macOS app for managing Claude Code Agent Skills with a Mac App Store-style interface. This release is intended for early technical testers.

## Highlights

- Native SwiftUI desktop app for macOS 14+.
- Rust `skill-cli` sidecar integrated with CC Switch without forking or patching the `cc-switch` submodule.
- Library view for installed skills, active/inactive/stub filters, row-level Claude/Codex/Gemini toggles, and detail-level app controls.
- Discover view for repository-backed skills, install-plan previews, install flow, and AgentShield rollback on blocked scans.
- Repositories, Updates, Backups, Settings, and Usage Insights views.
- Stub / Rehydrate flow for reclaiming disk while keeping a Library card.
- Local transcript-based Usage Insights with token/session/file/model/skill attribution.
- AgentShield security scanning for third-party install/import flows.
- WebDAV status, remote snapshot inspection, manual sync readiness diagnostics, and Settings-based config write.
- Local Agent library view for `~/.claude/agents`, Agent target diagnostics, AgencyAgents catalog preview, and Agent install-plan preview.
- Local release pipeline: development `.app`, DMG, release manifest, appcast generation, screenshot smoke, bundle smoke, and release doctor.

## Privacy And Local Data

- Popskill reads local CC Switch skill metadata and local Claude transcript JSONL files.
- Usage Insights aggregate transcript metadata locally and ignore message body text.
- WebDAV password input is passed to the sidecar through an environment variable and is not echoed in argv.
- Popskill-owned secrets should live in Keychain; they should not be committed, logged, or written to release manifests.

## Known Limits

- This is pre-alpha software. Expect rough edges.
- WebDAV manual Sync Now is not implemented yet because CC Switch upload/download logic currently crosses private Tauri state/module boundaries; `webdav-sync-plan` exposes that blocked readiness without mutating local or remote state.
- Sparkle 2.9.1 is linked and appcast generation is present, but public in-app update checks require a configured feed URL, public EdDSA key, and signed update payload.
- Public distribution requires Apple Developer ID signing and notarization.
- AgencyAgents catalog preview uses the GitHub API. Set `GITHUB_TOKEN` or `GH_TOKEN` if unauthenticated rate limits are hit.
- Package abstraction is a v0.2 roadmap item; v0.1 remains Skill-centered.

## Verification

The current local release gate is:

```bash
./scripts/ci-local.sh
./scripts/release-doctor.sh
```

`release-doctor` is expected to fail until Developer ID and notary credentials are configured. See [release-runbook.md](./release-runbook.md).
