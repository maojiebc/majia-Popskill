#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="${1:-$ROOT_DIR/skill-cli/target/debug/skill-cli}"
TMP_DIR="$(mktemp -d)"

if ! command -v jq > /dev/null; then
  echo "jq is required for skill-cli smoke tests. Install it with: brew install jq" >&2
  exit 127
fi

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

require_ok() {
  local name="$1"
  shift
  local output="$TMP_DIR/$name.json"

  "$CLI" "$@" > "$output"
  jq -e '.ok == true' "$output" > /dev/null

  printf "%s " "$name"
  jq -c '{ok, count: (if (.data | type) == "array" then (.data | length) else null end)}' "$output"
}

echo "==> Smoke testing skill-cli"

list_output="$TMP_DIR/list.json"
"$CLI" list --json > "$list_output"
jq -e '.ok == true and (.data | type) == "array"' "$list_output" > /dev/null
printf "list "
jq -c '{ok, count: (.data | length)}' "$list_output"

first_skill_id="$(jq -r '.data[0].id // empty' "$list_output")"
if [[ -n "$first_skill_id" ]]; then
  detail_output="$TMP_DIR/detail.json"
  "$CLI" detail "$first_skill_id" --json > "$detail_output"
  jq -e --arg id "$first_skill_id" '.ok == true and .data.id == $id' "$detail_output" > /dev/null
  echo "detail ok"
else
  echo "detail skipped: no installed skills"
fi

require_ok scan-unmanaged scan-unmanaged --json
require_ok backup-list backup-list --json
require_ok stub-list stub-list --json
require_ok repo-list repo-list --json
require_ok webdav-status webdav-status --json
webdav_sync_plan_output="$TMP_DIR/webdav-sync-plan.json"
"$CLI" webdav-sync-plan --json > "$webdav_sync_plan_output"
jq -e '.ok == true and .data.available == false and (.data.safeActions | index("webdav-status --json"))' \
  "$webdav_sync_plan_output" > /dev/null
echo "webdav-sync-plan ok"
require_ok security-scan-list security-scan-list --json

agent_root="$TMP_DIR/agents"
mkdir -p "$agent_root/engineering"
printf '%s\n' \
  '---' \
  'name: smoke-agent' \
  'description: Exercises Popskill agent-list smoke coverage.' \
  'tools: Read, Write' \
  'model: sonnet' \
  '---' \
  '# Smoke Agent' > "$agent_root/engineering/smoke-agent.md"
agent_list_output="$TMP_DIR/agent-list.json"
"$CLI" agent-list --root "$agent_root" --json > "$agent_list_output"
jq -e '
  .ok == true
  and (.data | length) == 1
  and .data[0].id == "engineering/smoke-agent"
  and .data[0].tools == ["Read", "Write"]
' "$agent_list_output" > /dev/null
echo "agent-list ok"

agent_targets_output="$TMP_DIR/agent-targets.json"
"$CLI" agent-targets --json > "$agent_targets_output"
jq -e '.ok == true and (.data | length) >= 10 and any(.data[]; .id == "claude-code")' \
  "$agent_targets_output" > /dev/null
echo "agent-targets ok"

agent_plan_home="$TMP_DIR/agent-plan-home"
mkdir -p "$agent_plan_home/.claude"
agent_plan_output="$TMP_DIR/agent-install-plan.json"
HOME="$agent_plan_home" "$CLI" agent-install-plan \
  msitarzewski/agency-agents:marketing/marketing-xiaohongshu-specialist \
  --target claude-code \
  --json > "$agent_plan_output"
jq -e '
  .ok == true
  and .data.targetId == "claude-code"
  and .data.requiresConversion == false
  and (.data.writes[0] | endswith("/.claude/agents/marketing-xiaohongshu-specialist.md"))
' "$agent_plan_output" > /dev/null
echo "agent-install-plan ok"

scan_dir="$TMP_DIR/security-scan-skill"
mkdir -p "$scan_dir"
printf '# Smoke Skill\n' > "$scan_dir/SKILL.md"
security_output="$TMP_DIR/security-scan.json"
POPSKILL_AGENTSHIELD_BIN=/bin/echo "$CLI" security-scan "$scan_dir" --json > "$security_output"
jq -e '.ok == true and .data.scanner == "ecc-agentshield" and .data.status == "verified"' "$security_output" > /dev/null
echo "security-scan ok"

isolated_home="$TMP_DIR/isolated-home"
unmanaged_name="popskill-smoke-unmanaged"
mkdir -p "$isolated_home/.claude/skills/$unmanaged_name"
printf '# Smoke Unmanaged Skill\n' > "$isolated_home/.claude/skills/$unmanaged_name/SKILL.md"
import_output="$TMP_DIR/import-unmanaged.json"
HOME="$isolated_home" POPSKILL_AGENTSHIELD_BIN=/bin/echo \
  "$CLI" import-unmanaged "$unmanaged_name" --app claude --json > "$import_output"
jq -e '.ok == true and .data[0].id == "local:popskill-smoke-unmanaged"' "$import_output" > /dev/null
HOME="$isolated_home" "$CLI" security-scan-list --json > "$TMP_DIR/import-scans.json"
jq -e '.ok == true and .data[0].skillId == "local:popskill-smoke-unmanaged" and .data[0].result.status == "verified"' \
  "$TMP_DIR/import-scans.json" > /dev/null
echo "import-unmanaged security gate ok"

blocked_scanner="$TMP_DIR/blocked-scanner.sh"
printf '#!/usr/bin/env bash\necho "High severity finding"\n' > "$blocked_scanner"
chmod +x "$blocked_scanner"
blocked_home="$TMP_DIR/blocked-home"
mkdir -p "$blocked_home/.claude/skills/$unmanaged_name"
printf '# Blocked Unmanaged Skill\n' > "$blocked_home/.claude/skills/$unmanaged_name/SKILL.md"
blocked_stderr="$TMP_DIR/import-blocked.err"
if HOME="$blocked_home" POPSKILL_AGENTSHIELD_BIN="$blocked_scanner" \
  "$CLI" import-unmanaged "$unmanaged_name" --app claude --json > /dev/null 2> "$blocked_stderr"; then
  echo "expected blocked unmanaged import to fail" >&2
  exit 1
fi
jq -e '.ok == false and (.error.message | contains("AgentShield blocked unmanaged skill"))' \
  "$blocked_stderr" > /dev/null
echo "import-unmanaged blocked gate ok"

health_output="$TMP_DIR/health.json"
"$CLI" health --json > "$health_output"
jq -e '.ok == true and (.data.installedCount | type) == "number"' "$health_output" > /dev/null
printf "health "
jq -c '{ok, installed: .data.installedCount, unmanaged: .data.unmanagedCount, backups: .data.backupCount, repositories: .data.repositoryCount, enabledRepositories: .data.enabledRepositoryCount, version: .data.sidecarVersion}' "$health_output"

missing_stderr="$TMP_DIR/missing-detail.err"
if "$CLI" detail "__popskill_missing_skill__" --json > /dev/null 2> "$missing_stderr"; then
  echo "expected missing detail command to fail" >&2
  exit 1
fi
jq -e '.ok == false and (.error.message | length > 0)' "$missing_stderr" > /dev/null
echo "error-envelope ok"
