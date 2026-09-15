#!/usr/bin/env bash
# coreai-stalk/scripts/lib/output.sh
# Padroniza paths de output em ./outputs/copys/{cliente}/inteligencia/ (relativo ao
# diretório de trabalho atual, a menos que STALK_OUTPUT_BASE seja definido)

set -euo pipefail

STALK_OUTPUT_BASE="${STALK_OUTPUT_BASE:-./outputs/copys}"
STALK_CONFIG_FILE="$HOME/.claude/skills/coreai-stalk/config.yaml"

# Lê valor de chave do config.yaml. Args: $1=chave
stalk_config_get() {
  local key="$1"
  local default="${2:-}"
  if [[ -f "$STALK_CONFIG_FILE" ]]; then
    local val
    val=$(grep -E "^${key}:" "$STALK_CONFIG_FILE" 2>/dev/null | head -1 | sed -E "s/^${key}:[[:space:]]*//" | tr -d '"' | tr -d "'")
    [[ -n "$val" ]] && echo "$val" && return
  fi
  echo "$default"
}

stalk_config_set() {
  local key="$1"
  local value="$2"

  mkdir -p "$(dirname "$STALK_CONFIG_FILE")"
  touch "$STALK_CONFIG_FILE"

  if grep -qE "^${key}:" "$STALK_CONFIG_FILE" 2>/dev/null; then
    sed -i '' "s|^${key}:.*|${key}: \"${value}\"|" "$STALK_CONFIG_FILE"
  else
    echo "${key}: \"${value}\"" >> "$STALK_CONFIG_FILE"
  fi
}

# Slugifica string para nome de pasta
stalk_slugify() {
  echo "$1" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g' \
    | sed -E 's/^-+|-+$//g' \
    | head -c 60
}

# Gera path de output. Args: $1=tipo (profile/search/dossie/comments/compare), $2=slug, $3=cliente (opcional)
stalk_output_dir() {
  local tipo="$1"
  local slug="$2"
  local cliente="${3:-$(stalk_config_get default_client default)}"

  local dir="$STALK_OUTPUT_BASE/$cliente/inteligencia/$tipo/$slug"
  mkdir -p "$dir"
  echo "$dir"
}

# Helper: imprime cabeçalho de output
stalk_print_header() {
  local titulo="$1"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  $titulo"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
}
