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

## Current Bridge

The current implementation is still SwiftUI plus Rust sidecar plus CC Switch. That is fine. The immediate bridge is:

- keep current `CapabilityPackage` output for UI stability
- expose domain primitives through `skill-cli domain-schema --json`
- keep mutating filesystem logic inside sidecar commands
- document every schema expansion in this file and `docs/ipc.md`

