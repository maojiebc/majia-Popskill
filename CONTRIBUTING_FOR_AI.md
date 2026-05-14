# Contributing For AI Agents

This file is the guardrail for AI-assisted development in Popskill. Read it before changing code. The goal is to keep Popskill moving toward a local AI asset control plane, not back into a page-by-page skill manager.

## Core Rule

Model the domain before changing the UI.

Popskill manages this chain:

```text
source -> package -> component -> deployment -> runtime
```

The SwiftUI app is an interaction layer. Filesystem writes, process management, config patching, security checks, updates, and rollback belong behind typed `skill-cli` commands or future application services.

## Required Boundaries

| Rule | Requirement |
|---|---|
| Domain first | Add or update Manifest, Lock, Deployment, Target, Runtime, Snapshot, and Adapter concepts before building page-specific behavior. |
| UI does not mutate system state | SwiftUI views may call typed commands, but must not directly edit third-party files, user configs, runtime processes, or target folders. |
| No overwrite config writes | Use read, validate, merge or patch, write, verify. Whole-file overwrite of third-party config is forbidden. |
| Mutations are transactional | Apply-style operations must follow plan, snapshot, apply, verify, commit. Roll back on apply or verify failure. |
| Errors are stable | New failure modes need stable codes, not only free-form strings. Preserve the JSON envelope documented in `docs/ipc.md`. |
| Secrets stay out of plain files | Store secret values in the OS secret store. JSON, SQLite, logs, argv, and screenshots may only carry secret references or sanitized state. |
| Symlink is optional | Symlink is a target-specific deployment strategy. The single source of truth must not depend on symlink discovery working. |
| Tests follow contracts | Every adapter, source connector, migration, schema, and rollback path needs tests at the contract boundary. |
| Docs version with APIs | Update `docs/asset-control-plane.md` and `docs/ipc.md` when schema, error codes, or command contracts change. |

## Preferred Implementation Order

1. Update the domain schema or command contract.
2. Add tests for the schema, adapter, or service behavior.
3. Implement sidecar or service logic.
4. Wire Swift models and view models.
5. Adjust views.
6. Run `./scripts/ci-local.sh`.

## Design Warnings

Avoid these shortcuts even when they look faster:

- Treating a skill, agent, CLI, or MCP server as unrelated page-specific data.
- Writing target folders as the source of truth.
- Assuming every target discovers symlinks.
- Replacing user config files instead of patching owned keys.
- Starting a local HTTP proxy for convenience.
- Putting runtime stdout, stderr, and protocol messages on the same channel.
- Making UI loading depend on synchronous filesystem scans.

## Sidecar Schema

`skill-cli domain-schema --json` exposes the current asset-control-plane primitives. Use it as the code-level contract for component kinds, deployment strategies, runtime transports, mutation phases, stable error codes, and invariants.

Before adding a new primitive, update:

- `skill-cli/src/main.rs`
- `docs/asset-control-plane.md`
- `docs/ipc.md`
- tests and smoke coverage

