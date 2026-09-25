#!/usr/bin/env bash
# Validate plugin manifests, MCP config, and skills for this repo.
set -euo pipefail

plugin_root="${PLUGIN_ROOT:-}"
if [[ -z "${plugin_root}" ]]; then
  plugin_root="$(find plugins -mindepth 1 -maxdepth 1 -type d | sort | head -1)"
fi

[[ -n "${plugin_root}" ]] || { echo "MISSING: plugin root"; exit 1; }
[[ -d "${plugin_root}" ]] || { echo "MISSING: ${plugin_root}"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "MISSING: jq"; exit 1; }

claude_manifest="${plugin_root}/.claude-plugin/plugin.json"
codex_manifest="${plugin_root}/.codex-plugin/plugin.json"
mcp_json="${plugin_root}/.mcp.json"
skills_dir="${plugin_root}/skills"

for file in "${claude_manifest}" "${codex_manifest}" "${mcp_json}"; do
  [[ -f "${file}" ]] || { echo "MISSING: ${file}"; exit 1; }
  jq empty "${file}"
done

for file in "${claude_manifest}" "${codex_manifest}"; do
  [[ "$(jq -er 'has("version")' "${file}")" == "false" ]] || {
    echo "FORBIDDEN: ${file} contains version"
    exit 1
  }
done

jq -er '.mcpServers | type == "object" and length > 0' "${mcp_json}" >/dev/null

# Claude Code plugin hooks are intentionally not shipped. Setup remains available
# as an explicit CLI command (`rtailscale setup check|repair|plugin-hook`).
[[ ! -e "${plugin_root}/hooks" ]] || { echo "FORBIDDEN: ${plugin_root}/hooks"; exit 1; }

[[ -d "${skills_dir}" ]] || { echo "MISSING: ${skills_dir}"; exit 1; }
skill_count=0
while IFS= read -r skill_file; do
  skill_count=$((skill_count + 1))
  grep -q '^name:' "${skill_file}" || { echo "MISSING name: ${skill_file}"; exit 1; }
  grep -q '^description:' "${skill_file}" || { echo "MISSING description: ${skill_file}"; exit 1; }
done < <(find "${skills_dir}" -mindepth 2 -maxdepth 2 -name SKILL.md | sort)
(( skill_count > 0 )) || { echo "MISSING: ${skills_dir}/*/SKILL.md"; exit 1; }

echo "OK"
