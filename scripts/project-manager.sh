#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
PROJECTS_DIR="$ROOT_DIR/Shaping Projects"
ARCHIVE_DIR="$PROJECTS_DIR/_archived"
CONFIG_DIR="$ROOT_DIR/.shaping-config"
KNOWN_REPOS_FILE="$CONFIG_DIR/known-repos.json"
ORG="deseretdigital"

mkdir -p "$ARCHIVE_DIR" "$CONFIG_DIR"
[[ -f "$KNOWN_REPOS_FILE" ]] || echo '[]' > "$KNOWN_REPOS_FILE"

# Global return variables (bash 3.2 has no namerefs)
_RESULT=""
_RESULT_ARRAY=()

# ─── Terminal helpers ───────────────────────────────────────────────

bold()  { printf '\033[1m%s\033[0m' "$*"; }
green() { printf '\033[32m%s\033[0m' "$*"; }
dim()   { printf '\033[2m%s\033[0m' "$*"; }

hide_cursor() { printf '\033[?25l'; }
show_cursor() { printf '\033[?25h'; }
move_up()     { printf '\033[%dA' "$1"; }
clear_line()  { printf '\033[2K\r'; }

cleanup() { show_cursor; stty echo 2>/dev/null; }
trap cleanup EXIT

# ─── Read a single keypress (handles arrow keys) ───────────────────

read_key() {
  local key
  IFS= read -rsn1 key
  if [[ "$key" == $'\x1b' ]]; then
    local seq
    IFS= read -rsn2 seq
    case "$seq" in
      '[A') echo "UP" ;;
      '[B') echo "DOWN" ;;
      *)    echo "ESC" ;;
    esac
  elif [[ "$key" == "" ]]; then
    echo "ENTER"
  elif [[ "$key" == " " ]]; then
    echo "SPACE"
  else
    echo "$key"
  fi
}

# ─── Single-select menu (arrow keys + enter) ──────────────────────
# Sets _RESULT to the chosen value.

select_one() {
  local prompt="$1"
  shift
  local options=("$@")
  local count=${#options[@]}
  local cursor=0

  hide_cursor
  printf '\n'
  bold "$prompt"; printf '\n'
  dim "  ↑/↓ to move, Enter to select"; printf '\n\n'

  for i in "${!options[@]}"; do
    if [[ $i -eq $cursor ]]; then
      printf '  \033[36m❯ %s\033[0m\n' "${options[$i]}"
    else
      printf '    %s\n' "${options[$i]}"
    fi
  done

  while true; do
    local key
    key=$(read_key)
    case "$key" in
      UP)    (( cursor > 0 )) && (( cursor-- )) || true ;;
      DOWN)  (( cursor < count - 1 )) && (( cursor++ )) || true ;;
      ENTER)
        move_up $((count + 3))
        for (( i=0; i<count+4; i++ )); do clear_line; printf '\n'; done
        move_up $((count + 4))
        printf '  %s: %s\n' "$prompt" "$(green "${options[$cursor]}")"
        show_cursor
        _RESULT="${options[$cursor]}"
        return
        ;;
    esac
    move_up "$count"
    for i in "${!options[@]}"; do
      clear_line
      if [[ $i -eq $cursor ]]; then
        printf '  \033[36m❯ %s\033[0m\n' "${options[$i]}"
      else
        printf '    %s\n' "${options[$i]}"
      fi
    done
  done
}

# ─── Multi-select menu (arrow keys, space to toggle, enter to confirm)
# Pre-selected items should be prefixed with "+".
# Sets _RESULT_ARRAY to the selected values (without "+" prefix).

multi_select() {
  local prompt="$1"
  shift
  local options=() selected=()

  for item in "$@"; do
    if [[ "$item" == +* ]]; then
      options+=("${item#+}")
      selected+=(1)
    else
      options+=("$item")
      selected+=(0)
    fi
  done

  local count=${#options[@]}
  local cursor=0
  local total=$((count + 2))

  hide_cursor
  printf '\n'
  bold "$prompt"; printf '\n'
  dim "  ↑/↓ move, Space toggle, Enter confirm"; printf '\n\n'

  _draw_multi_menu() {
    local c="$1"
    for i in "${!options[@]}"; do
      local marker="○"
      [[ ${selected[$i]} -eq 1 ]] && marker="●"
      if [[ $i -eq $c ]]; then
        printf '  \033[36m❯ [%s] %s\033[0m\n' "$marker" "${options[$i]}"
      else
        printf '    [%s] %s\n' "$marker" "${options[$i]}"
      fi
    done
    if [[ $c -eq $count ]]; then
      printf '  \033[36m❯ + Add new repository...\033[0m\n'
    else
      printf '    + Add new repository...\n'
    fi
    if [[ $c -eq $((count + 1)) ]]; then
      printf '  \033[32m❯ ✓ Done\033[0m\n'
    else
      printf '    ✓ Done\n'
    fi
  }

  _draw_multi_menu "$cursor"

  while true; do
    local key
    key=$(read_key)
    case "$key" in
      UP)   (( cursor > 0 )) && (( cursor-- )) || true ;;
      DOWN) (( cursor < total - 1 )) && (( cursor++ )) || true ;;
      SPACE)
        if (( cursor < count )); then
          selected[$cursor]=$(( 1 - ${selected[$cursor]} ))
        fi
        ;;
      ENTER)
        if [[ $cursor -eq $count ]]; then
          # "Add new..." selected
          show_cursor
          move_up "$total"
          for (( i=0; i<total; i++ )); do clear_line; printf '\n'; done
          move_up "$total"
          printf '  Enter repository name (without org): '
          local new_repo
          read -r new_repo
          if [[ -n "$new_repo" ]]; then
            options+=("$new_repo")
            selected+=(1)
            count=${#options[@]}
            total=$((count + 2))
            add_known_repo "$new_repo"
          fi
          hide_cursor
          clear_line; bold "$prompt"; printf '\n'
          clear_line; dim "  ↑/↓ move, Space toggle, Enter confirm"; printf '\n\n'
          _draw_multi_menu "$cursor"
          continue
        elif [[ $cursor -eq $((count + 1)) ]]; then
          # "Done" — collect results
          move_up $((total + 3))
          for (( i=0; i<total+4; i++ )); do clear_line; printf '\n'; done
          move_up $((total + 4))
          _RESULT_ARRAY=()
          for i in "${!options[@]}"; do
            [[ ${selected[$i]} -eq 1 ]] && _RESULT_ARRAY+=("${options[$i]}")
          done
          local display
          display=$(IFS=', '; echo "${_RESULT_ARRAY[*]}")
          printf '  %s: %s\n' "$prompt" "$(green "$display")"
          show_cursor
          return
        fi
        ;;
    esac
    move_up "$total"
    _draw_multi_menu "$cursor"
  done
}

# ─── JSON / config helpers ─────────────────────────────────────────

get_known_repos() {
  python3 -c "
import json
with open('$KNOWN_REPOS_FILE') as f:
    repos = json.load(f)
for r in sorted(set(repos)):
    print(r)
"
}

add_known_repo() {
  local repo="$1"
  python3 -c "
import json
with open('$KNOWN_REPOS_FILE') as f:
    repos = json.load(f)
repos.append('$repo')
repos = sorted(set(repos))
with open('$KNOWN_REPOS_FILE', 'w') as f:
    json.dump(repos, f, indent=2)
"
}

write_project_json() {
  local outfile="$1"
  shift
  # Remaining args: repos..., then "---", then notion docs...
  local repos=() notions=() in_notions=0
  for arg in "$@"; do
    if [[ "$arg" == "---" ]]; then
      in_notions=1
      continue
    fi
    if [[ $in_notions -eq 0 ]]; then
      repos+=("$arg")
    else
      notions+=("$arg")
    fi
  done

  local repos_json notions_json
  repos_json=$(printf '%s\n' "${repos[@]}" | python3 -c "import sys,json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))")
  if [[ ${#notions[@]} -gt 0 ]]; then
    notions_json=$(printf '%s\n' "${notions[@]}" | python3 -c "import sys,json; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))")
  else
    notions_json="[]"
  fi

  python3 -c "
import json
org = '$ORG'
repos = $repos_json
notions = $notions_json
data = {
    'repositories': [{'org': org, 'repo': r} for r in repos],
    'notion_docs': notions
}
with open('$outfile', 'w') as f:
    json.dump(data, f, indent=2)
    f.write('\n')
"
}

# ─── Notion doc input ──────────────────────────────────────────────
# Sets _RESULT_ARRAY to the full list of notion docs.

prompt_notion_docs() {
  local existing=("${@+"$@"}")

  # If there are existing docs, use a multi-select to keep/remove them
  if [[ ${#existing[@]} -gt 0 ]]; then
    # Build options: all pre-selected (prefixed with "+")
    local doc_options=()
    for d in "${existing[@]}"; do
      doc_options+=("+$d")
    done
    multi_select_notion "Notion documents (deselect to remove)" "${doc_options[@]}"
    existing=("${_RESULT_ARRAY[@]+"${_RESULT_ARRAY[@]}"}")
  fi

  # Prompt to add new docs
  printf '\n'
  bold "Add Notion documents"; printf '\n'
  dim "  Enter Notion URLs/names one per line. Empty line to finish."; printf '\n'

  local new_docs=()
  while true; do
    printf '  > '
    local line
    read -r line
    [[ -z "$line" ]] && break
    new_docs+=("$line")
  done

  _RESULT_ARRAY=()
  if [[ ${#existing[@]} -gt 0 ]]; then
    for d in "${existing[@]}"; do _RESULT_ARRAY+=("$d"); done
  fi
  if [[ ${#new_docs[@]} -gt 0 ]]; then
    for d in "${new_docs[@]}"; do _RESULT_ARRAY+=("$d"); done
  fi
}

# ─── Multi-select for notion docs (no "Add new" row, just toggle + done)
# Pre-selected items prefixed with "+". Sets _RESULT_ARRAY.

multi_select_notion() {
  local prompt="$1"
  shift
  local options=() selected=()

  for item in "$@"; do
    if [[ "$item" == +* ]]; then
      options+=("${item#+}")
      selected+=(1)
    else
      options+=("$item")
      selected+=(0)
    fi
  done

  local count=${#options[@]}
  local cursor=0
  local total=$((count + 1))  # options + Done

  hide_cursor
  printf '\n'
  bold "$prompt"; printf '\n'
  dim "  ↑/↓ move, Space toggle, Enter confirm"; printf '\n\n'

  _draw_notion_menu() {
    local c="$1"
    for i in "${!options[@]}"; do
      local marker="○"
      [[ ${selected[$i]} -eq 1 ]] && marker="●"
      # Truncate long URLs for display
      local label="${options[$i]}"
      if [[ ${#label} -gt 70 ]]; then
        label="${label:0:67}..."
      fi
      if [[ $i -eq $c ]]; then
        printf '  \033[36m❯ [%s] %s\033[0m\n' "$marker" "$label"
      else
        printf '    [%s] %s\n' "$marker" "$label"
      fi
    done
    if [[ $c -eq $count ]]; then
      printf '  \033[32m❯ ✓ Done\033[0m\n'
    else
      printf '    ✓ Done\n'
    fi
  }

  _draw_notion_menu "$cursor"

  while true; do
    local key
    key=$(read_key)
    case "$key" in
      UP)   (( cursor > 0 )) && (( cursor-- )) || true ;;
      DOWN) (( cursor < total - 1 )) && (( cursor++ )) || true ;;
      SPACE)
        if (( cursor < count )); then
          selected[$cursor]=$(( 1 - ${selected[$cursor]} ))
        fi
        ;;
      ENTER)
        if [[ $cursor -eq $count ]]; then
          # "Done" — collect results
          move_up $((total + 3))
          for (( i=0; i<total+4; i++ )); do clear_line; printf '\n'; done
          move_up $((total + 4))
          _RESULT_ARRAY=()
          for i in "${!options[@]}"; do
            [[ ${selected[$i]} -eq 1 ]] && _RESULT_ARRAY+=("${options[$i]}")
          done
          local kept=${#_RESULT_ARRAY[@]}
          printf '  %s: %s\n' "$prompt" "$(green "$kept doc(s) kept")"
          show_cursor
          return
        fi
        ;;
    esac
    move_up "$total"
    _draw_notion_menu "$cursor"
  done
}

# ─── Numbering helper ──────────────────────────────────────────────

# Find the next project number by scanning existing folder prefixes.
next_project_number() {
  local max=0
  local dir
  for dir in "$PROJECTS_DIR" "$ARCHIVE_DIR"; do
    for d in "$dir"/*/; do
      [[ ! -d "$d" ]] && continue
      local name
      name="$(basename "$d")"
      if [[ "$name" =~ ^([0-9]+) ]]; then
        local num=$((10#${BASH_REMATCH[1]}))
        (( num > max )) && max=$num
      fi
    done
  done
  printf '%03d' $((max + 1))
}

# ─── Planning state template ───────────────────────────────────────

generate_planning_state() {
  local project_dir="$1"
  local project_name="$2"
  local project_json="$project_dir/project.json"

  # Build research items from project.json
  local research_items
  research_items=$(python3 -c "
import json
with open('$project_json') as f:
    data = json.load(f)
lines = []
for doc in data.get('notion_docs', []):
    lines.append('- Review Notion doc for project scope and requirements')
    break
for repo in data.get('repositories', []):
    lines.append('- Research \`{org}/{repo}\` for existing implementation'.format(**repo))
print('\n'.join(lines))
")

  local sources_items
  sources_items=$(python3 -c "
import json
with open('$project_json') as f:
    data = json.load(f)
lines = []
for doc in data.get('notion_docs', []):
    lines.append('- [Notion: {name}]({url})'.format(name='$project_name', url=doc))
for repo in data.get('repositories', []):
    lines.append('- [{org}/{repo}](https://github.com/{org}/{repo})'.format(**repo))
print('\n'.join(lines) if lines else '- _None yet._')
")

  cat > "$project_dir/planning-state.md" <<EOF
# Planning State — $project_name

## Identified So Far
_No research completed yet._

## Still Needs Research
$research_items
- Identify data models, APIs, and migration paths

## Unanswered Questions
- _None yet — initial shaping session has not been run._

## Research Sources
$sources_items
EOF
}

# ─── Commands ──────────────────────────────────────────────────────

cmd_new() {
  printf '\n'
  bold "━━━ Create New Shaping Project ━━━"; printf '\n\n'

  printf '  Project name: '
  read -r project_name
  if [[ -z "$project_name" ]]; then
    echo "Error: project name required." >&2; exit 1
  fi

  local number
  number=$(next_project_number)
  local folder_name="$number $project_name"

  local project_dir="$PROJECTS_DIR/$folder_name"
  if [[ -d "$project_dir" ]]; then
    echo "Error: project '$folder_name' already exists." >&2; exit 1
  fi

  # Repo selection
  local known_repos=()
  while IFS= read -r line; do
    known_repos+=("$line")
  done < <(get_known_repos)

  multi_select "Repositories" "${known_repos[@]}"
  local selected_repos=("${_RESULT_ARRAY[@]+"${_RESULT_ARRAY[@]}"}")

  # Notion docs
  prompt_notion_docs
  local notion_docs=("${_RESULT_ARRAY[@]+"${_RESULT_ARRAY[@]}"}")

  # Create project
  mkdir -p "$project_dir"

  local write_args=()
  if [[ ${#selected_repos[@]} -gt 0 ]]; then
    for r in "${selected_repos[@]}"; do write_args+=("$r"); done
  fi
  write_args+=("---")
  if [[ ${#notion_docs[@]} -gt 0 ]]; then
    for n in "${notion_docs[@]}"; do write_args+=("$n"); done
  fi
  write_project_json "$project_dir/project.json" "${write_args[@]}"

  # Create standard files
  cat > "$project_dir/Features.md" <<EOF
# $project_name — Features

<!-- Required features to complete the project -->
EOF

  cat > "$project_dir/Services.md" <<EOF
# $project_name — Services

<!-- Services that will be created or updated -->
EOF

  generate_planning_state "$project_dir" "$project_name"

  printf '\n'
  green "✓ Created project: $folder_name"; printf '\n'
  printf '  %s\n' "$project_dir"
  printf '  project.json:\n'
  python3 -m json.tool "$project_dir/project.json" | sed 's/^/    /'
  printf '\n'
}

cmd_update() {
  printf '\n'
  bold "━━━ Update Shaping Project ━━━"; printf '\n'

  # List projects
  local projects=()
  while IFS= read -r d; do
    [[ "$(basename "$d")" == "_archived" ]] && continue
    [[ -f "$d/project.json" ]] && projects+=("$(basename "$d")")
  done < <(find "$PROJECTS_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

  if [[ ${#projects[@]} -eq 0 ]]; then
    echo "No projects with project.json found." >&2; exit 1
  fi

  select_one "Select project" "${projects[@]}"
  local chosen_project="$_RESULT"

  local project_dir="$PROJECTS_DIR/$chosen_project"
  local project_json="$project_dir/project.json"

  # Load current repos and notion docs
  local current_repos=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && current_repos+=("$line")
  done < <(python3 -c "
import json
with open('$project_json') as f: data = json.load(f)
for r in data.get('repositories', []):
    print(r['repo'])
")

  local current_notions=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && current_notions+=("$line")
  done < <(python3 -c "
import json
with open('$project_json') as f: data = json.load(f)
for n in data.get('notion_docs', []):
    print(n)
")

  # Build repo options: known repos, with current ones pre-selected
  local known_repos=()
  while IFS= read -r line; do
    known_repos+=("$line")
  done < <(get_known_repos)

  # Merge known + current, dedupe
  local all_repos=()
  for r in "${known_repos[@]}"; do all_repos+=("$r"); done
  for r in "${current_repos[@]}"; do all_repos+=("$r"); done
  local sorted_repos=()
  while IFS= read -r line; do
    sorted_repos+=("$line")
  done < <(printf '%s\n' "${all_repos[@]}" | sort -u)

  local repo_options=()
  for r in "${sorted_repos[@]}"; do
    local prefix=""
    for cr in "${current_repos[@]}"; do
      [[ "$cr" == "$r" ]] && prefix="+" && break
    done
    repo_options+=("${prefix}${r}")
  done

  multi_select "Repositories" "${repo_options[@]}"
  local selected_repos=("${_RESULT_ARRAY[@]+"${_RESULT_ARRAY[@]}"}")

  # Notion docs
  prompt_notion_docs "${current_notions[@]+"${current_notions[@]}"}"
  local notion_docs=("${_RESULT_ARRAY[@]+"${_RESULT_ARRAY[@]}"}")

  # Write updated json
  local write_args=()
  if [[ ${#selected_repos[@]} -gt 0 ]]; then
    for r in "${selected_repos[@]}"; do write_args+=("$r"); done
  fi
  write_args+=("---")
  if [[ ${#notion_docs[@]} -gt 0 ]]; then
    for n in "${notion_docs[@]}"; do write_args+=("$n"); done
  fi
  write_project_json "$project_json" "${write_args[@]}"

  printf '\n'
  green "✓ Updated project: $chosen_project"; printf '\n'
  python3 -m json.tool "$project_json" | sed 's/^/    /'
  printf '\n'
}

cmd_archive() {
  printf '\n'
  bold "━━━ Archive Shaping Project ━━━"; printf '\n'

  local projects=()
  while IFS= read -r d; do
    [[ "$(basename "$d")" == "_archived" ]] && continue
    projects+=("$(basename "$d")")
  done < <(find "$PROJECTS_DIR" -mindepth 1 -maxdepth 1 -type d | sort)

  if [[ ${#projects[@]} -eq 0 ]]; then
    echo "No projects to archive." >&2; exit 1
  fi

  select_one "Select project to archive" "${projects[@]}"
  local chosen_project="$_RESULT"

  mv "$PROJECTS_DIR/$chosen_project" "$ARCHIVE_DIR/$chosen_project"

  printf '\n'
  green "✓ Archived: $chosen_project → _archived/"; printf '\n\n'
}

# ─── Main ──────────────────────────────────────────────────────────

case "${1:-}" in
  new)     cmd_new ;;
  update)  cmd_update ;;
  archive) cmd_archive ;;
  *)
    echo "Usage: $0 {new|update|archive}" >&2
    exit 1
    ;;
esac
