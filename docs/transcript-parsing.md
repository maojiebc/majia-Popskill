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
- `attributionSkill`
- `attributionPlugin`
- `attributionAgent`

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
- skill-level usage totals when a `message.usage` record includes top-level `attributionSkill`
- recent session activity sorted by latest `timestamp`

Recent session labels prefer the transcript `cwd` field so names like `projects/skill-creator` preserve meaningful hyphens. If `cwd` is absent, Popskill falls back to a compact suffix derived from the encoded Claude project folder name.

Skill attribution is intentionally conservative: Popskill only attributes token usage to a skill when Claude Code writes `attributionSkill` on the same JSONL record as `message.usage`. Records without that marker remain part of session and model totals, but are not guessed into a skill bucket.

## Privacy and Interpretation Boundary

Popskill scans transcript files on the local Mac only. The scanner reads JSONL records to extract envelope metadata and `message.usage` counters, but message `content` is ignored and is not stored, displayed, uploaded, or used for ranking.

The current UI labels skill numbers as attributed events. They are exact for records that contain `attributionSkill`, but they are not a complete accounting of all usage because many transcript events have no skill marker.

## Attribution Status

The original plan assumed a stable `<command-name>` marker for skill invocation. Real local transcripts instead expose a stronger top-level marker:

- `attributionSkill`, for example `baoyu-image-gen`
- `attributionPlugin`, for example `baoyu-skills`
- `attributionAgent`, for agent-side attribution such as `general-purpose`

Popskill now uses `attributionSkill` for Usage and Token Spend skill rows. Idle Candidates also consults the same attribution data and excludes skills used within the last 60 days. Message content remains ignored throughout.
