#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="$SCRIPT_DIR/folders.json"

die() { printf 'open-project: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<'EOF'
open-project — cd into a registered project folder and run `claude` in the foreground.

USAGE
  ./open-project.sh <alias>
  ./open-project.sh --list
  ./open-project.sh --help

The <alias> must be a key in folders.json. To register one, use:
  ./claude-autorun.sh --add <alias> <path>
EOF
}

ensure_registry() {
  [[ -f "$REGISTRY" ]] || printf '{}\n' > "$REGISTRY"
}

list_aliases() {
  ensure_registry
  if [[ "$(jq 'length' "$REGISTRY")" == "0" ]]; then
    echo "(no aliases registered — use: ./claude-autorun.sh --add <alias> <path>)"
    return 0
  fi
  jq -r 'to_entries | sort_by(.key)[] | "\(.key)\t\(.value)"' "$REGISTRY" \
    | awk -F'\t' '{ printf "  %-20s  %s\n", $1, $2 }'
}

main() {
  if [[ $# -eq 0 ]]; then
    usage; exit 0
  fi

  case "$1" in
    -h|--help) usage; exit 0 ;;
    --list)    list_aliases; exit 0 ;;
    -*)        die "unknown flag: $1 (try --help)" ;;
  esac

  local alias="$1"
  ensure_registry

  local folder
  folder="$(jq -r --arg k "$alias" '.[$k] // empty' "$REGISTRY")"
  [[ -n "$folder" ]] || die "no such alias: '$alias'. Try: ./open-project.sh --list"
  [[ -d "$folder" ]] || die "alias '$alias' points to a missing directory: $folder"

  command -v claude >/dev/null 2>&1 || die "the 'claude' CLI is not on \$PATH."

  cd "$folder"
  exec claude agents
}

main "$@"
