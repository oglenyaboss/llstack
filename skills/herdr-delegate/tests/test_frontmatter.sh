#!/usr/bin/env bash
# The stable skills are discovered by their frontmatter, so it must parse as
# strict YAML and it must stay short enough for a skill listing.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

frontmatter() {
  awk 'NR == 1 && $0 != "---" { exit } NR > 1 && $0 == "---" { exit } NR > 1 { print }' "$1"
}

case_frontmatter_contract() {
  local file dir name value desc bad=""
  for file in "$ROOT/SKILL.md" "$ROOT/../pr-risk/SKILL.md"; do
    [[ -f "$file" ]] || t_fail "missing $file"
    dir="$(basename "$(dirname "$file")")"

    name="$(frontmatter "$file" | sed -n 's/^name:[[:space:]]*//p')"
    [[ -n "$name" ]] || t_fail "$dir: no name in frontmatter"
    assert_eq "$dir" "$name" "$dir: name matches directory"
    [[ "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || t_fail "$dir: name [$name] is not lowercase-hyphenated"
    (( ${#name} <= 64 )) || t_fail "$dir: name longer than 64 characters"

    desc="$(frontmatter "$file" | sed -n 's/^description:[[:space:]]*//p')"
    [[ -n "$desc" ]] || t_fail "$dir: no description in frontmatter"
    [[ "$desc" == \"*\" && "$desc" == *\" ]] || t_fail "$dir: description must be a quoted scalar"
    value="${desc:1:${#desc}-2}"
    [[ "$value" != *'"'* ]] || t_fail "$dir: description has an inner quote"
    (( ${#value} >= 20 )) || t_fail "$dir: description shorter than 20 characters"
    (( ${#value} <= 180 )) || t_fail "$dir: description is ${#value} characters, limit 180"
  done

  while IFS= read -r file; do
    while IFS= read -r line; do
      [[ "$line" =~ ^[a-z-]+:\ (.*)$ ]] || continue
      value="${BASH_REMATCH[1]}"
      [[ "$value" == \"* || "$value" == \'* ]] && continue
      [[ "$value" == *": "* || "$value" == *" #"* ]] && bad+="${file#"$ROOT"/}: $line; "
    done < <(frontmatter "$file")
  done < <(printf '%s\n' "$ROOT/SKILL.md" "$ROOT/../pr-risk/SKILL.md")
  [[ -z "$bad" ]] || t_fail "unquoted ': ' or ' #' in frontmatter breaks strict YAML parsers: $bad"
}

run_case frontmatter_contract case_frontmatter_contract
