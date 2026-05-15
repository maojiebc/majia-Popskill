# Popskill Asset Control Plane

This document turns the May 2026 deep research recommendations into Popskill's working architecture contract. It is deliberately independent of the current SwiftUI shell, so the model can survive future UI or runtime changes.

## Positioning

Popskill is not just a skill browser. It is a local AI asset control plane for capabilities installed on a machine.

The canonical chain is:

```text
source -> package -> component -> deployment -> runtime
```

| Layer | Meaning | Examples |
|---|---|---|
| Source | Where an asset comes from | local folder, Git repository, ZIP, registry, MCP endpoint |
| Package | User-facing install and update unit | Feishu/Lark bundle, PDF package, single skill wrapper |
| Component | Concrete capability inside a package | skill, CLI, MCP server, agent, rule, prompt, config |
| Deployment | Projection of a component into a target | copy into Codex skills, patch Claude config, wrapper script |
| Runtime | Executable or long-lived process | CLI, MCP server over stdio, agent sidecar |

## Single Source Of Truth

Popskill-owned state is the source of truth. Target folders are projections.

This matters because target discovery behavior differs across AI tools. Symlinks can be useful, but they cannot be the only truth. The default deployment posture is:

1. `copy`
2. `configPatch`
3. `wrapper`
4. `symlink`

Targets may override this order only after adapter-level verification proves the target handles the strategy.

## Manifest Shape

The long-term manifest is intentionally close to the sidecar schema exposed by `skill-cli domain-schema --json`.

```json
{
  "schemaVersion": 1,
  "id": "pkg:lark",
  "displayName": "Feishu / Lark",
  "packageType": "composite",
  "source": {
    "id": "builtin:lark",
    "kind": "local",
    "locator": "popskill/builtin/lark",
    "versionMode": "pinned",
    "resolvedVersion": "0.1.0",
    "contentHash": "sha256..."
  },
  "components": [
    {
      "id": "lark-doc",
      "kind": "skill",
      "displayName": "Lark Doc",
      "entry": "skills/lark-doc/SKILL.md",
      "runtime": null,
      "compatibility": [
        {
          "targetId": "codex",
          "supported": true,
          "preferredStrategy": "copy"
        }
      ]
    }
  ]
}
```

## Deployment Transaction

Every mutating deployment must be staged:

| Phase | Action | Failure behavior |
|---|---|---|
| Plan | Compute target path, strategy, permissions, and conflicts | Return an error, no writes |
| Snapshot | Back up affected user files or directories | Abort if snapshot fails |
| Apply | Copy, symlink, patch config, create wrapper, or spawn process | Roll back immediately on failure |
| Verify | Check existence, hash, target discovery, and runtime health | Roll back on verification failure |
| Commit | Persist deployment state and logs | Only after apply and verify succeed |

Rollback must record whether it was attempted and whether it succeeded.

## Adapter Contract

Adapters own target-specific behavior. They must not leak target quirks into view code.

| Method | Responsibility |
|---|---|
| `probe()` | Detect whether a target is available and which scopes are usable |
| `planApply(component)` | Choose deployment strategy and target paths |
| `apply(plan)` | Execute a plan after snapshot creation |
| `remove(component)` | Remove only Popskill-owned projections |
| `health(component)` | Check drift, discoverability, process health, and config integrity |

Adapter tests should use real folder fixtures and cover copy fallback, symlink rejection, config merge conflict, verify failure, and rollback.

## Stable Error Codes

These codes are part of the sidecar contract:

| Code | Meaning |
|---|---|
| `E_TARGET_NOT_FOUND` | Target is not registered or not detected |
| `E_STRATEGY_UNSUPPORTED` | Target cannot use the requested deployment strategy |
| `E_CONFIG_MERGE_CONFLICT` | Config cannot be merged without risking user data |
| `E_SECRET_UNAVAILABLE` | A secret reference could not be resolved |
| `E_PROCESS_TIMEOUT` | Runtime did not become healthy before timeout |
| `E_VERIFY_FAILED` | Apply completed but verification failed |
| `E_ROLLBACK_FAILED` | Rollback was attempted but failed |

## SQLite Direction

When Popskill introduces its own durable asset database, the baseline should be WAL plus FTS5.

```sql
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

CREATE TABLE packages (
  id TEXT PRIMARY KEY,
  source_id TEXT NOT NULL,
  display_name TEXT NOT NULL,
  package_type TEXT NOT NULL,
  resolved_version TEXT,
  content_hash TEXT,
  updated_at TEXT NOT NULL
);

CREATE VIRTUAL TABLE search_docs USING fts5(
  package_id UNINDEXED,
  name,
  summary,
  trigger_scenario,
  readme_excerpt,
  tokenize = 'unicode61'
);
```

The UI should read cached package and search state first, then let background jobs refresh disk, source, and update status.

## Content-Addressable Store (v0.2 Reserve)

This section reserves design space for v0.2. It is not implemented in v0.1.
Full source material in [architecture-reference-skillctl.md](./architecture-reference-skillctl.md) (Chinese, archived from a 2026-05-15 design session).

The current `source -> package -> component -> deployment -> runtime` chain is conceptually complete but operationally thin in one spot: there is no dedicated **content-addressable store** between `source` and `deployment`. v0.2 introduces that layer.

### Proposed three-tier layout

```text
~/.popskill/sources/      # upstream origins (local source / git / archive)
   <package-id>/          # mutable: dev symlink to ~/projects/<repo>
   <package-id>@<ver>/    # immutable: pinned snapshot from registry / archive

~/.popskill/store/        # content-addressable, one physical copy
   <package-id>@<ver>-<hash4>/   # tag = first 4 hex of sha256(SKILL.md + key files)
                                 # multiple versions coexist

~/.popskill/projections/  # one per target agent, symlink-based
   claude/skills/<name>      -> ../../store/<package-id>@<ver>-<hash4>/
   codex/skills/<name>       -> ../../store/<package-id>@<other-ver>-<hash4>/
```

Targets (`~/.claude/skills/`, `~/.codex/skills/`, etc.) symlink once to the corresponding `projections/<target>/skills/` directory. From v0.2 on, popskill never writes into target directories directly; it only renders projection trees.

### Five hard invariants (from architecture-reference-skillctl.md)

1. **Plugin namespace is read-only sidetrack.** `anthropic-skills:*` and host-app plugin skills never enter `store/`. `skill-cli doctor --inventory` surfaces them as `external` namespace, no projection, no hijack.
2. **Projection is the sole agent-visible surface.** Whole-directory symlink preferred; per-file symlink as fallback after probe testing.
3. **Lockfile is truth, symlink is render.** `projections/<target>/lock.toml` holds the per-agent pinned state. Symlink tree can be rebuilt from lockfile at any time without data loss.
4. **Mutable must be explicit.** Default `store/` entries are immutable snapshots. Dev mode (pointing at `~/projects/<repo>`) sets `mutable = true` + `observed_hash` in lockfile; doctor flags hash drift instead of pretending the entry is frozen.
5. **`id` first, `name`/`alias` second.** Stable reverse-domain `id = "com.author.skill"` is the dedup primary key. `name` is for display and trigger; `aliases = [...]` handles historical renames. Legacy entries without `id` get synthetic ids and a doctor "please add `id`" hint.

### Lockfile shape (per target)

```toml
# ~/.popskill/projections/claude/lock.toml

[[skills]]
id = "com.majia.guanyuan"
name = "majia-guanyuan"
version = "2.1.4"
hash = "sha256:7f3a..."
store = "majia-guanyuan@2.1.4-7f3a"
source = "local:/Users/majia/projects/majia-guanyuan"
mutable = false
aliases = ["guanyuan-majia"]
```

Each target's lockfile is independent. Claude can run a new version while Codex temporarily pins an older one — that is the whole point of per-target pinning, and it is the strongest reason to introduce `store/` at all.

### Concretely deferred from v0.1

- v0.1 keeps SQLite as the operational SSOT. SQLite is the runtime cache and search index. v0.2 lockfile is the human-readable view + cross-device sync medium, not a replacement.
- v0.1 does not add the `id` column. The v0.1.x patch cycle introduces `id` with a SQLite migration that generates synthetic ids (`gen:{owner}.{name}`) for legacy rows.
- v0.1 does not implement projection rendering. v0.1 still uses `copy` / `configPatch` / `wrapper` / `symlink` deployment strategies directly. v0.2 promotes `symlink-from-projection` to the default after target-agent `_probe` tests pass.

### Probe gate before v0.2 work begins

Before writing any `store/` or `projections/` code, v0.2 must run the `_probe` empirical test matrix described in [architecture-reference-skillctl.md §7](./architecture-reference-skillctl.md): a minimal `_probe` skill with `version: B` in the physical store and `version: A` at the projection symlink, executed against each target (Claude Code / Codex / Cursor / OpenClaw / Hermes) to confirm the agent actually reads through the symlink chain instead of caching its own copy.

If any target fails the whole-directory symlink probe, the v0.2 design must accept per-file symlink fallback for that target before any production rollout.

## Current Bridge

The current implementation is still SwiftUI plus Rust sidecar plus CC Switch. That is fine. The immediate bridge is:

- keep current `CapabilityPackage` output for UI stability
- expose domain primitives through `skill-cli domain-schema --json`
- keep mutating filesystem logic inside sidecar commands
- document every schema expansion in this file and `docs/ipc.md`

