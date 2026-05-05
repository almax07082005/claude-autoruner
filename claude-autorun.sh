#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="$SCRIPT_DIR/folders.json"
ORCHESTRATOR_NAME="autoruner-orchestrator"

usage() {
  cat <<'EOF'
claude-autorun — launch Claude Code sessions with --rc + auto mode preconfigured.

Run from inside the claude-autoruner folder as `./claude-autorun.sh <args>`.

USAGE
  ./claude-autorun.sh <alias-or-path> [session-name]   Launch a child session (detached, --rc).
  ./claude-autorun.sh --orchestrator                   Launch the orchestrator (foreground, in this folder).
  ./claude-autorun.sh --add <alias> <path>             Register a folder alias.
  ./claude-autorun.sh --remove <alias>                 Remove an alias.
  ./claude-autorun.sh --list                           List aliases.
  ./claude-autorun.sh --help                           Show this help.

NOTES
  - <alias-or-path> may be a registered alias OR a literal directory path.
  - <session-name> defaults to "<alias-or-basename>-<YYYYMMDD-HHMM>".
  - Child sessions run inside a detached tmux session,
    so they keep a real PTY and can be re-attached locally with:
        tmux attach -t <name>
EOF
}

die()  { printf 'claude-autorun: %s\n' "$*" >&2; exit 1; }
warn() { printf 'claude-autorun: %s\n' "$*" >&2; }

require_claude() {
  command -v claude >/dev/null 2>&1 || die "the 'claude' CLI is not on \$PATH. Install Claude Code first."
}

ensure_registry() {
  [[ -f "$REGISTRY" ]] || printf '{}\n' > "$REGISTRY"
}

resolve_alias() {
  # echo absolute path if $1 is a known alias, else empty
  ensure_registry
  jq -r --arg k "$1" '.[$k] // empty' "$REGISTRY"
}

list_aliases() {
  ensure_registry
  if [[ "$(jq 'length' "$REGISTRY")" == "0" ]]; then
    echo "(no aliases registered — use: claude-autorun --add <alias> <path>)"
    return 0
  fi
  jq -r 'to_entries | sort_by(.key)[] | "\(.key)\t\(.value)"' "$REGISTRY" \
    | awk -F'\t' '{ printf "  %-20s  %s\n", $1, $2 }'
}

add_alias() {
  local alias="$1" path="$2"
  [[ -n "$alias" && -n "$path" ]] || die "usage: claude-autorun --add <alias> <path>"
  [[ "$alias" =~ ^[A-Za-z0-9_.-]+$ ]] || die "alias must match [A-Za-z0-9_.-]+"
  [[ -d "$path" ]] || die "not a directory: $path"
  local abs
  abs="$(cd "$path" && pwd)"
  ensure_registry
  local tmp
  tmp="$(mktemp)"
  jq --arg k "$alias" --arg v "$abs" '. + {($k): $v}' "$REGISTRY" > "$tmp"
  mv "$tmp" "$REGISTRY"
  echo "registered: $alias -> $abs"
}

remove_alias() {
  local alias="$1"
  [[ -n "$alias" ]] || die "usage: claude-autorun --remove <alias>"
  ensure_registry
  if [[ "$(jq --arg k "$alias" 'has($k)' "$REGISTRY")" != "true" ]]; then
    die "no such alias: $alias"
  fi
  local tmp
  tmp="$(mktemp)"
  jq --arg k "$alias" 'del(.[$k])' "$REGISTRY" > "$tmp"
  mv "$tmp" "$REGISTRY"
  echo "removed: $alias"
}

default_session_name() {
  local label="$1"
  printf '%s-%s' "$label" "$(date +%Y%m%d-%H%M)"
}

spawn_detached() {
  # Spawn `claude --rc --permission-mode auto --name "$name"` in $folder
  # inside a detached tmux session.
  local folder="$1" name="$2"
  local cmd=(claude --rc --permission-mode auto --name "$name")

  command -v tmux >/dev/null 2>&1 || die "tmux is not installed. Install it with: brew install tmux"

  if tmux has-session -t "=$name" 2>/dev/null; then
    die "tmux session named '$name' already exists. Pick another name or run: tmux kill-session -t '$name'"
  fi

  ( cd "$folder" && tmux new-session -d -s "$name" "${cmd[@]}" )
  echo "launched [tmux] session '$name' in $folder"
  echo "  attach locally: tmux attach -t '$name'"
  echo "  kill:           tmux kill-session -t '$name'"
}

launch_child() {
  local arg="$1" name="${2:-}"
  local folder=""
  local label=""

  local resolved
  resolved="$(resolve_alias "$arg")"
  if [[ -n "$resolved" ]]; then
    folder="$resolved"
    label="$arg"
  elif [[ -d "$arg" ]]; then
    folder="$(cd "$arg" && pwd)"
    label="$(basename "$folder")"
  else
    die "'$arg' is not a registered alias and not a directory. Try: claude-autorun --list"
  fi

  [[ -n "$name" ]] || name="$(default_session_name "$label")"

  require_claude
  spawn_detached "$folder" "$name"
}

launch_orchestrator() {
  require_claude
  echo "starting orchestrator in $SCRIPT_DIR (foreground; pair iPhone Claude app once)..."
  cd "$SCRIPT_DIR"
  exec claude --rc --permission-mode auto --name "$ORCHESTRATOR_NAME"
}

main() {
  if [[ $# -eq 0 ]]; then
    usage; exit 0
  fi

  case "$1" in
    -h|--help)        usage; exit 0 ;;
    --list)           list_aliases; exit 0 ;;
    --add)            shift; add_alias "${1:-}" "${2:-}"; exit 0 ;;
    --remove)         shift; remove_alias "${1:-}"; exit 0 ;;
    --orchestrator)   launch_orchestrator ;;
    -*)               die "unknown flag: $1 (try --help)" ;;
    *)                launch_child "$1" "${2:-}" ;;
  esac
}

main "$@"
