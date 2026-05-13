# Popskill IPC

Popskill talks to CC Switch through the `skill-cli` sidecar. The SwiftUI app never writes `~/.cc-switch/cc-switch.db` directly.

## Response Envelope

Every successful command writes JSON to stdout:

```json
{
  "ok": true,
  "data": {}
}
```

Every failed command writes JSON to stderr and exits non-zero:

```json
{
  "ok": false,
  "error": {
    "code": "COMMAND_FAILED",
    "message": "context: root cause"
  }
}
```

## Commands

### `skill-cli health --json`

Returns local sidecar and CC Switch diagnostics used by Settings.

```json
{
  "ok": true,
  "data": {
    "sidecarVersion": "0.1.0",
    "installedCount": 61,
    "unmanagedCount": 0,
    "backupCount": 10,
    "repositoryCount": 13,
    "enabledRepositoryCount": 12,
    "skillStorePath": "/Users/example/.cc-switch/skills",
    "skillBackupPath": "/Users/example/.cc-switch/skill-backups"
  }
}
```

### `skill-cli webdav-status --json`

Returns saved CC Switch WebDAV sync settings with secrets removed.

```json
{
  "ok": true,
  "data": {
    "configured": true,
    "enabled": true,
    "autoSync": false,
    "baseUrl": "https://dav.example.com/remote.php/dav/files/me",
    "username": "me",
    "remoteRoot": "cc-switch-sync",
    "profile": "default",
    "status": {
      "lastSyncAt": 1778603190,
      "lastError": null
    }
  }
}
```

When WebDAV has not been configured:

```json
{
  "ok": true,
  "data": {
    "configured": false
  }
}
```

### `skill-cli webdav-configure --base-url <url> --username <user> --password-env <env> --remote-root <root> --profile <profile> --enabled <true|false> --auto-sync <true|false> --json`

Writes CC Switch WebDAV sync settings and returns the same sanitized payload as `webdav-status`. Password values are only accepted through an environment variable so they do not appear in argv; omitting `--password-env` keeps the existing saved password.

```json
{
  "ok": true,
  "data": {
    "configured": true,
    "enabled": true,
    "autoSync": false,
    "baseUrl": "https://dav.example.com/remote.php/dav/files/me",
    "username": "me",
    "remoteRoot": "cc-switch-sync",
    "profile": "default",
    "status": {
      "lastSyncAt": null,
      "lastError": null
    }
  }
}
```

### `skill-cli webdav-remote-info --json`

Fetches remote manifest information for the saved enabled WebDAV config. This command fails if WebDAV is unconfigured or disabled.

```json
{
  "ok": true,
  "data": {
    "deviceName": "Mac Studio",
    "createdAt": 1778603190,
    "snapshotId": "snapshot-123",
    "version": 1,
    "protocolVersion": 1,
    "dbCompatVersion": 3,
    "compatible": true,
    "artifacts": ["database", "skills"],
    "layout": "profile",
    "remotePath": "cc-switch-sync/default"
  }
}
```

When no compatible remote snapshot exists, CC Switch returns:

```json
{
  "ok": true,
  "data": {
    "empty": true
  }
}
```

### `skill-cli list --json`

Returns all skills currently managed by CC Switch.

```json
{
  "ok": true,
  "data": [
    {
      "id": "owner/repo:directory",
      "name": "skill-name",
      "description": "Skill description",
      "directory": "skill-name",
      "repoOwner": "owner",
      "repoName": "repo",
      "readmeUrl": "https://github.com/owner/repo/blob/HEAD/skill/SKILL.md",
      "apps": {
        "claude": false,
        "codex": true,
        "gemini": false,
        "opencode": false,
        "hermes": false
      },
      "installedAt": 1778602730,
      "updatedAt": 0,
      "contentHash": "sha256..."
    }
  ]
}
```

### `skill-cli agent-list [--root <agents-dir>] --json`

Returns local Claude Code agents from `~/.claude/agents`. This command is read-only and is not backed by CC Switch. Popskill treats Agent files as role/persona definitions, separate from Skill packages.

```json
{
  "ok": true,
  "data": [
    {
      "id": "engineering/backend-architect",
      "name": "backend-architect",
      "description": "Designs service boundaries and production-ready backend plans.",
      "fileName": "backend-architect.md",
      "path": "/Users/example/.claude/agents/engineering/backend-architect.md",
      "category": "engineering",
      "tools": ["Read", "Write", "Bash"],
      "model": "sonnet",
      "lastModifiedAt": 1778603190,
      "sizeBytes": 2048
    }
  ]
}
```

### `skill-cli agent-targets --json`

Returns read-only diagnostics for Agent-capable tools and the local paths Popskill would use for future Agent install/toggle work. The initial target matrix follows AgencyAgents' supported tools and stays diagnostic-only in v0.1.

```json
{
  "ok": true,
  "data": [
    {
      "id": "kimi",
      "name": "Kimi Code",
      "scope": "user",
      "format": "agent-yaml",
      "paths": ["/Users/example/.config/kimi/agents"],
      "detected": true,
      "source": "agency-agents",
      "note": "AgencyAgents emits agent.yaml plus system.md per agent."
    }
  ]
}
```

### `skill-cli toggle <skill-id> --app <app> --enabled <true|false> --json`

Enables or disables an installed skill for one target app. The command delegates to `SkillService::toggle_app`, so CC Switch remains the source of truth for DB updates and skill symlinks.

Supported app values:

- `claude`
- `codex`
- `gemini`
- `opencode`
- `hermes`

Response:

```json
{
  "ok": true,
  "data": {
    "id": "owner/repo:directory",
    "app": "codex",
    "enabled": true
  }
}
```

### `skill-cli scan-unmanaged --json`

Returns local skills found in app skill directories that are not currently managed by CC Switch. This command is read-only.

```json
{
  "ok": true,
  "data": [
    {
      "directory": "local-skill",
      "name": "local-skill",
      "description": "Local skill description",
      "found_in": ["claude"],
      "path": "/Users/example/.claude/skills/local-skill"
    }
  ]
}
```

### `skill-cli discover [--query <text>] [--limit <n>] --json`

Returns installable skills from enabled CC Switch skill repositories. The command also includes installed status, so Discover can disable install buttons for existing skills.

```json
{
  "ok": true,
  "data": [
    {
      "key": "owner/repo:directory",
      "name": "skill-name",
      "description": "Skill description",
      "directory": "directory",
      "readmeUrl": "https://github.com/owner/repo/blob/main/directory/SKILL.md",
      "installed": false,
      "repoOwner": "owner",
      "repoName": "repo",
      "repoBranch": "main"
    }
  ]
}
```

### `skill-cli repo-list --json`

Returns CC Switch skill repositories used by Discover.

```json
{
  "ok": true,
  "data": [
    {
      "owner": "anthropics",
      "name": "skills",
      "branch": "main",
      "enabled": true
    }
  ]
}
```

### `skill-cli repo-add --owner <owner> --name <name> --branch <branch> --enabled <true|false> --json`

Adds or replaces one CC Switch skill repository used by Discover.

`owner` and `name` are trimmed, `name` strips a trailing `.git`, and both segments must be non-empty without slashes or whitespace.

```json
{
  "ok": true,
  "data": {
    "owner": "example",
    "name": "skills",
    "branch": "main",
    "enabled": true
  }
}
```

### `skill-cli repo-toggle --owner <owner> --name <name> --enabled <true|false> --json`

Enables or disables one configured skill repository. Installed skills are not modified.

`owner` and `name` follow the same normalization rules as `repo-add`.

```json
{
  "ok": true,
  "data": {
    "owner": "anthropics",
    "name": "skills",
    "enabled": false
  }
}
```

### `skill-cli repo-remove --owner <owner> --name <name> --json`

Removes one configured skill repository from CC Switch discovery sources. Installed skills are not uninstalled.

`owner` and `name` follow the same normalization rules as `repo-add`.

```json
{
  "ok": true,
  "data": {
    "owner": "anthropics",
    "name": "skills"
  }
}
```

### `skill-cli install-plan <skill-key> --app <app> --json`

Returns a read-only preview for one discoverable skill install. The plan includes the target app, source repository, planned SSOT/app paths, existing skill conflict if present, and the current AgentShield gate behavior.

```json
{
  "ok": true,
  "data": {
    "skillKey": "owner/repo:directory",
    "name": "skill-name",
    "targetApp": "codex",
    "installDirectory": "directory",
    "source": {
      "repoOwner": "owner",
      "repoName": "repo",
      "repoBranch": "main"
    },
    "writes": {
      "ssotPath": "/Users/example/.cc-switch/skills/directory",
      "appSkillPath": "/Users/example/.codex/skills/directory"
    },
    "securityGate": "agentShieldPostInstallRollback",
    "steps": [
      "downloadFromRepository",
      "copyToSkillStore",
      "enableTargetApp",
      "runAgentShield",
      "rollbackIfBlocked"
    ]
  }
}
```

### `skill-cli install <skill-key> --app <app> --json`

Applies one discoverable skill install.

Discovers the skill by key, installs it through CC Switch, enables it for the requested app, then runs AgentShield against the installed SSOT directory. `blocked` results are persisted, the install is rolled back with CC Switch uninstall, and the command exits with an error. `warning` and `unavailable` results are persisted but allowed.

Pass `--skip-security-scan` only for local development bypasses.

```json
{
  "ok": true,
  "data": {
    "id": "owner/repo:directory",
    "name": "skill-name",
    "directory": "directory"
  }
}
```

### `skill-cli detail <skill-id> --json`

Returns one installed skill by id. The shape matches one item from `list`.

```json
{
  "ok": true,
  "data": {
    "id": "owner/repo:directory",
    "name": "skill-name",
    "description": "Skill description",
    "directory": "skill-name",
    "apps": {
      "claude": false,
      "codex": true,
      "gemini": false,
      "opencode": false,
      "hermes": false
    }
  }
}
```

### `skill-cli uninstall <skill-id> --json`

Uninstalls one managed skill through CC Switch. CC Switch removes app-folder copies/symlinks, deletes the SSOT skill directory, removes the DB record, and creates an uninstall backup when possible.

```json
{
  "ok": true,
  "data": {
    "backupPath": "/Users/example/.cc-switch/skill-backups/..."
  }
}
```

### `skill-cli stub-list --json`

Returns Popskill stubs. Stubs are local metadata records in `~/.popskill/stubs.json` that point at CC Switch uninstall backups.

```json
{
  "ok": true,
  "data": [
    {
      "skill": {
        "id": "owner/repo:directory",
        "name": "skill-name",
        "directory": "directory"
      },
      "backupId": "20260512_162451_skill-name",
      "backupPath": "/Users/example/.cc-switch/skill-backups/20260512_162451_skill-name",
      "stubbedAt": 1778603190
    }
  ]
}
```

### `skill-cli stub <skill-id> --json`

Converts one installed skill into a Popskill stub. The command reads the installed metadata, delegates uninstall + backup creation to CC Switch, then stores the recoverable metadata in `~/.popskill/stubs.json`.

```json
{
  "ok": true,
  "data": {
    "skill": {
      "id": "owner/repo:directory",
      "name": "skill-name",
      "directory": "directory"
    },
    "backupId": "20260512_162451_skill-name",
    "backupPath": "/Users/example/.cc-switch/skill-backups/20260512_162451_skill-name",
    "stubbedAt": 1778603190
  }
}
```

### `skill-cli rehydrate <skill-id> --app <app> --json`

Restores one Popskill stub from its stored CC Switch backup and enables it for the requested app. On success, the stub metadata is removed.

```json
{
  "ok": true,
  "data": {
    "id": "owner/repo:directory",
    "name": "skill-name",
    "directory": "directory"
  }
}
```

### `skill-cli security-scan <skill-dir> [--skill-id <skill-id>] --json`

Runs a third-party skill directory through ECC AgentShield. By default the sidecar invokes `npx --yes ecc-agentshield <skill-dir>`. Set `POPSKILL_AGENTSHIELD_BIN` to point at a pinned local scanner binary/script.

The command returns `ok: true` even when findings are present; callers must inspect `data.status`. When `--skill-id` is provided, Popskill stores the result in `~/.popskill/security-scans.json` for Library badges.

```json
{
  "ok": true,
  "data": {
    "scanner": "ecc-agentshield",
    "status": "verified",
    "summary": "AgentShield completed without reported findings",
    "exitCode": 0,
    "stdout": "...",
    "stderr": "",
    "scannedAt": 1778603190
  }
}
```

Status values:

- `verified`: scanner completed without obvious findings
- `warning`: scanner reported lower-confidence findings or exited non-zero without blocking keywords
- `blocked`: scanner reported high/critical/malicious findings
- `unavailable`: scanner command could not be launched

### `skill-cli security-scan-list --json`

Returns persisted AgentShield scan results for currently installed skills. Records for uninstalled/stubbed skills are pruned on read.

```json
{
  "ok": true,
  "data": [
    {
      "skillId": "owner/repo:directory",
      "skillDirectory": "/Users/example/.cc-switch/skills/directory",
      "result": {
        "scanner": "ecc-agentshield",
        "status": "verified",
        "summary": "AgentShield completed without reported findings",
        "exitCode": 0,
        "stdout": "",
        "stderr": "",
        "scannedAt": 1778603190
      }
    }
  ]
}
```

### `skill-cli backup-list --json`

Returns uninstall backups created by CC Switch.

```json
{
  "ok": true,
  "data": [
    {
      "backupId": "20260512_162451_skill-name",
      "backupPath": "/Users/example/.cc-switch/skill-backups/20260512_162451_skill-name",
      "createdAt": 1778603091,
      "skill": {
        "id": "owner/repo:directory",
        "name": "skill-name",
        "directory": "directory"
      }
    }
  ]
}
```

### `skill-cli backup-restore <backup-id> --app <app> --json`

Restores one uninstall backup into CC Switch's managed skill store and enables it for the requested app.

```json
{
  "ok": true,
  "data": {
    "id": "owner/repo:directory",
    "name": "skill-name",
    "directory": "directory"
  }
}
```

### `skill-cli backup-delete <backup-id> --json`

Deletes one uninstall backup directory through CC Switch.

```json
{
  "ok": true,
  "data": {
    "backupId": "20260512_162451_skill-name"
  }
}
```

### `skill-cli import-unmanaged <directory> [--app <app>]... --json`

Imports one unmanaged local skill directory into CC Switch. If no `--app` is provided, it enables Claude by default. Popskill runs AgentShield against the unmanaged source path before import; `blocked` results stop the import. Pass `--skip-security-scan` only for local development bypasses.

```json
{
  "ok": true,
  "data": [
    {
      "id": "local:directory",
      "name": "skill-name",
      "directory": "directory"
    }
  ]
}
```

### `skill-cli check-updates --json`

Checks GitHub-backed installed skills for remote content changes. This can take a while because CC Switch downloads source repository archives to compare content hashes.

```json
{
  "ok": true,
  "data": [
    {
      "id": "owner/repo:directory",
      "name": "skill-name",
      "currentHash": "local-sha256",
      "remoteHash": "remote-sha256"
    }
  ]
}
```

### `skill-cli update <skill-id> --json`

Updates one installed skill from its GitHub source. CC Switch handles the download, hash recompute, database write, and app-directory sync for enabled apps.

```json
{
  "ok": true,
  "data": {
    "id": "owner/repo:directory",
    "name": "skill-name",
    "contentHash": "new-sha256"
  }
}
```
