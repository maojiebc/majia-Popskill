# Transcript Parsing Notes

Popskill Insights reads Claude transcript JSONL files locally from `~/.claude/projects`. It must not upload transcript content.

## Observed Field Paths

Initial field-path inspection on 2026-05-13 found usage data under assistant messages:

- `message.usage.input_tokens`
- `message.usage.output_tokens`
- `message.usage.cache_creation_input_tokens`
- `message.usage.cache_read_input_tokens`
- `message.usage.cache_creation.ephemeral_1h_input_tokens`
- `message.usage.cache_creation.ephemeral_5m_input_tokens`
- `message.usage.server_tool_use.web_fetch_requests`
- `message.usage.server_tool_use.web_search_requests`

Useful envelope fields:

- `sessionId`
- `timestamp`
- `cwd`
- `type`
- `message.role`
- `message.model`

## Current MVP Strategy

The Insights MVP computes aggregate usage without storing or displaying message text:

- transcript files scanned
- sessions observed
- assistant usage events
- input tokens
- output tokens
- cache creation tokens
- cache read tokens
- total tokens
- model-level usage totals
- recent session activity sorted by latest `timestamp`

Recent session labels prefer the transcript `cwd` field so names like `projects/skill-creator` preserve meaningful hyphens. If `cwd` is absent, Popskill falls back to a compact suffix derived from the encoded Claude project folder name.

## Attribution Status

The original plan assumed a stable `<command-name>` marker for skill invocation. The initial scan did not verify that marker, so skill-level token attribution remains pending.

Likely attribution signals to evaluate next:

- local-agent-mode skill session paths in `cwd`
- project path segments containing skill names
- attachment records that list available skills
- sidechain/session boundaries
