#!/usr/bin/env bash
[[ "${HERDR_ENV:-}" == 1 ]] || exit 0
dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
agents="$("$dir/hd" ls 2>/dev/null)" || exit 0
[[ -n "$agents" ]] || exit 0
printf 'herdr-delegate: you are the lead; these agents are still running (name role status pane):\n%s\n\n' "$agents"
cat "$dir/SKILL.md"
