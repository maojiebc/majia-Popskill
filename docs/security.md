# Security Notes

Popskill manages local automation skills, so it should treat credentials and executable skill content as high-trust surfaces.

## Secret Storage

Popskill-owned secrets must not be stored in SQLite, JSON config files, logs, or transcript-derived Insights tables.

Use macOS Keychain through `KeychainService` for:

- GitHub PAT
- skills.sh or registry credentials
- LLM API keys used by future sandbox/test features

The default Keychain service name is:

```text
app.popskill.secrets
```

SQLite may store a boolean like `webdav_configured = true` or a non-secret username/server URL, but never the password/token itself.

WebDAV is currently delegated to CC Switch settings because the sync implementation lives there. Popskill does not store a second copy of the WebDAV password; when saving a new password it passes the value to `skill-cli` through an environment variable, and `webdav-status` always returns a sanitized payload. `webdav-sync-plan` is read-only and returns sync readiness metadata without touching local or remote state.

## Skill Content

Install/update/import operations are delegated to CC Switch so Popskill does not duplicate filesystem safety logic. UI actions that remove or overwrite local skill content should stay user-triggered and visibly reversible where CC Switch provides a backup.

Catalog-provided source/readme links should only open `http` or `https` URLs. Unsupported schemes are ignored and Popskill falls back to the repository URL when owner/name metadata is available.

## Transcript Insights

Insights should aggregate numeric fields and metadata only. Do not display or persist message text unless the user explicitly asks for a transcript inspection workflow.
