#!/bin/bash
# yt-text-batch: Processa multiplos videos do YouTube em sequencia
# Usa yt-text.sh para cada video e mostra dashboard consolidado

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
YT_TEXT="$SCRIPT_DIR/yt-text.sh"

# Cores
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_DIM="\033[2m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_RED="\033[31m"
C_CYAN="\033[36m"
C_WHITE="\033[37m"

show_help() {
  cat <<'HELP'
=== yt-text-batch - Transcricao em Lote ===

Uso:
  yt-text-batch.sh <url1> <url2> ... [--lang idioma]
  yt-text-batch.sh --file lista.txt [--lang idioma]

Parametros:
  url1 url2 ...   URLs do YouTube (separadas por espaco)
  --file FILE     Arquivo .txt com uma URL por linha
  --lang IDIOMA   Idioma das legendas (padrao: pt)

Exemplos:
  yt-text-batch.sh "https://youtube.com/watch?v=abc" "https://youtube.com/watch?v=def"
  yt-text-batch.sh --file meus-videos.txt --lang pt
HELP
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" || $# -eq 0 ]]; then
  show_help
  exit 0
fi

# --- Parsear argumentos ---
URLS=()
LANG="pt"
FILE_MODE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --lang)
      LANG="${2:-pt}"
      shift 2
      ;;
    --file)
      FILE_MODE="$2"
      shift 2
      ;;
    --help|-h)
      show_help
      exit 0
      ;;
    *)
      URLS+=("$1")
      shift
      ;;
  esac
done

# Carregar URLs do arquivo se --file
if [ -n "$FILE_MODE" ]; then
  if [ ! -f "$FILE_MODE" ]; then
    echo "ERRO: Arquivo nao encontrado: $FILE_MODE"
    exit 1
  fi
  while IFS= read -r line; do
    line=$(echo "$line" | tr -d '[:space:]')
    [[ -z "$line" || "$line" == \#* ]] && continue
    URLS+=("$line")
  done < "$FILE_MODE"
fi

if [ ${#URLS[@]} -eq 0 ]; then
  echo "ERRO: Nenhuma URL fornecida."
  show_help
  exit 1
fi

TOTAL=${#URLS[@]}
BATCH_START=$(date +%s)

# Arrays para resultados
declare -a RESULT_STATUS=()
declare -a RESULT_TITLE=()
declare -a RESULT_DURATION=()
declare -a RESULT_TOKENS=()
declare -a RESULT_COST=()
declare -a RESULT_TIME=()
declare -a RESULT_OUTPUT=()

# --- Header ---
printf "\n"
printf "${C_BOLD}${C_CYAN}╔══════════════════════════════════════════════════════════════════╗${C_RESET}\n"
printf "${C_CYAN}║${C_RESET}  ${C_BOLD}yt-text-batch${C_RESET} ${C_DIM}— Transcricao em Lote${C_RESET}                           ${C_CYAN}║${C_RESET}\n"
printf "${C_CYAN}║${C_RESET}  ${C_DIM}${TOTAL} videos para processar | Idioma: ${LANG}${C_RESET}                         ${C_CYAN}║${C_RESET}\n"
printf "${C_CYAN}╚══════════════════════════════════════════════════════════════════╝${C_RESET}\n"
printf "\n"

BATCH_TOTAL_TOKENS=0
BATCH_TOTAL_COST=0

for i in "${!URLS[@]}"; do
  NUM=$((i + 1))
  URL="${URLS[$i]}"

  printf "${C_BOLD}${C_CYAN}━━━ Video ${NUM}/${TOTAL} ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}\n"
  printf "${C_DIM}URL: ${URL}${C_RESET}\n\n"

  VIDEO_START=$(date +%s)

  # Executar yt-text.sh
  if bash "$YT_TEXT" "$URL" "$LANG"; then
    RESULT_STATUS+=("OK")
  else
    RESULT_STATUS+=("ERRO")
  fi

  VIDEO_TIME=$(( $(date +%s) - VIDEO_START ))
  RESULT_TIME+=("$VIDEO_TIME")

  # Buscar metadata do video mais recente no outputs/videos
  PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
  LATEST_DIR=$(ls -td "$PROJECT_ROOT/outputs/videos/"*/ 2>/dev/null | head -1)

  if [ -n "$LATEST_DIR" ] && [ -f "$LATEST_DIR/metadata.json" ]; then
    RESULT_TITLE+=("$(jq -r '.video_title // "?"' "$LATEST_DIR/metadata.json" | cut -c1-50)")
    RESULT_DURATION+=("$(jq -r '.duration_seconds // 0' "$LATEST_DIR/metadata.json")")

    local_input=$(jq -r '.total_input_tokens // 0' "$LATEST_DIR/metadata.json")
    local_output=$(jq -r '.total_output_tokens // 0' "$LATEST_DIR/metadata.json")
    local_tokens=$((local_input + local_output))
    local_cost=$(jq -r '.total_cost_usd // "0"' "$LATEST_DIR/metadata.json")

    RESULT_TOKENS+=("$local_tokens")
    RESULT_COST+=("$local_cost")
    RESULT_OUTPUT+=("$LATEST_DIR")

    BATCH_TOTAL_TOKENS=$((BATCH_TOTAL_TOKENS + local_tokens))
    BATCH_TOTAL_COST=$(awk "BEGIN { printf \"%.6f\", $BATCH_TOTAL_COST + $local_cost }")
  else
    RESULT_TITLE+=("Desconhecido")
    RESULT_DURATION+=("0")
    RESULT_TOKENS+=("0")
    RESULT_COST+=("0")
    RESULT_OUTPUT+=("-")
  fi

  printf "\n"
done

# --- Relatorio final ---
BATCH_TIME=$(( $(date +%s) - BATCH_START ))
BATCH_MINS=$((BATCH_TIME / 60))
BATCH_SECS=$((BATCH_TIME % 60))
BATCH_TOTAL_K=$((BATCH_TOTAL_TOKENS / 1000))
BATCH_COST_FMT=$(awk "BEGIN { printf \"\$%.4f\", $BATCH_TOTAL_COST }")

printf "\n"
printf "${C_BOLD}${C_GREEN}╔══════════════════════════════════════════════════════════════════╗${C_RESET}\n"
printf "${C_GREEN}║${C_RESET}  ${C_BOLD}${C_GREEN}✓ LOTE COMPLETO${C_RESET}                                                ${C_GREEN}║${C_RESET}\n"
printf "${C_GREEN}╠══════════════════════════════════════════════════════════════════╣${C_RESET}\n"
printf "${C_GREEN}║${C_RESET}                                                                  ${C_GREEN}║${C_RESET}\n"

# Tabela de resultados
printf "${C_GREEN}║${C_RESET}  ${C_BOLD}#  Status  Tempo   Tokens   Custo    Video${C_RESET}                   ${C_GREEN}║${C_RESET}\n"
printf "${C_GREEN}║${C_RESET}  ${C_DIM}─────────────────────────────────────────────────────────────${C_RESET}  ${C_GREEN}║${C_RESET}\n"

for i in "${!RESULT_STATUS[@]}"; do
  NUM=$((i + 1))
  STATUS="${RESULT_STATUS[$i]}"
  VTIME="${RESULT_TIME[$i]}"
  VTOKENS="${RESULT_TOKENS[$i]}"
  VCOST="${RESULT_COST[$i]}"
  VTITLE="${RESULT_TITLE[$i]}"

  VMINS=$((VTIME / 60))
  VSECS=$((VTIME % 60))
  VTK=$((VTOKENS / 1000))
  VCOST_FMT=$(awk "BEGIN { printf \"\$%.3f\", $VCOST }")

  if [ "$STATUS" = "OK" ]; then
    STATUS_FMT="${C_GREEN}OK${C_RESET}    "
  else
    STATUS_FMT="${C_RED}ERRO${C_RESET}  "
  fi

  TITLE_SHORT="$VTITLE"
  if [ ${#TITLE_SHORT} -gt 25 ]; then
    TITLE_SHORT="${TITLE_SHORT:0:22}..."
  fi

  printf "${C_GREEN}║${C_RESET}  ${C_WHITE}%d${C_RESET}  ${STATUS_FMT} ${C_WHITE}%2dm%02ds${C_RESET}  ${C_WHITE}%4dk${C_RESET}  ${C_WHITE}%-8s${C_RESET} ${C_DIM}%-25s${C_RESET}  ${C_GREEN}║${C_RESET}\n" \
    "$NUM" "$VMINS" "$VSECS" "$VTK" "$VCOST_FMT" "$TITLE_SHORT"
done

printf "${C_GREEN}║${C_RESET}  ${C_DIM}─────────────────────────────────────────────────────────────${C_RESET}  ${C_GREEN}║${C_RESET}\n"
printf "${C_GREEN}║${C_RESET}                                                                  ${C_GREEN}║${C_RESET}\n"
printf "${C_GREEN}║${C_RESET}  ${C_BOLD}Total:${C_RESET}  ${C_WHITE}${TOTAL} videos${C_RESET} | ${C_WHITE}${BATCH_MINS}m ${BATCH_SECS}s${C_RESET} | ${C_WHITE}${BATCH_TOTAL_K}k tokens${C_RESET} | ${C_GREEN}${C_BOLD}${BATCH_COST_FMT}${C_RESET}   ${C_GREEN}║${C_RESET}\n"
printf "${C_GREEN}║${C_RESET}                                                                  ${C_GREEN}║${C_RESET}\n"
printf "${C_GREEN}╚══════════════════════════════════════════════════════════════════╝${C_RESET}\n"
