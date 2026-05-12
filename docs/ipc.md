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

### `skill-cli toggle <skill-id> --app <app> --enabled <true|false>`

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

### `skill-cli install <skill-key> --app <app> --json`

Discovers the skill by key, installs it through CC Switch, and enables it for the requested app.

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
