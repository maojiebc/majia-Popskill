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
