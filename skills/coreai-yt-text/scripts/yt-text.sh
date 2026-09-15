#!/bin/bash
# yt-text: Extrai transcricao nativa do YouTube + formata com Gemini Flash 2.5
# Sem download de video - apenas captions/legendas
# Dashboard visual com progresso, tokens e custo

set -euo pipefail

# --- Help inline ---
show_help() {
  cat <<'HELP'
=== yt-text - Transcricao YouTube via Captions + Gemini ===

Uso: yt-text.sh <url-youtube>

Parametros:
  url         URL do video do YouTube (obrigatorio)

Comportamento:
  - Detecta automaticamente o idioma nativo do video
  - Baixa legendas no idioma original
  - Traduz e formata tudo em portugues (pt-BR) via Gemini

Exemplos:
  yt-text.sh "https://www.youtube.com/watch?v=abc123"
  yt-text.sh "https://youtu.be/abc123"
HELP
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  show_help
  exit 0
fi

# --- Source lib compartilhada ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../_shared/lib.sh
source "$SCRIPT_DIR/../../_shared/lib.sh"

# --- Validacao de dependencias ---
check_dependency yt-dlp "brew install yt-dlp"
check_dependency jq "brew install jq"
check_dependency curl "xcode-select --install"

# --- Carregar .env do projeto se existir ---
ENV_FILE="$SCRIPT_DIR/../../../.env"
if [ -f "$ENV_FILE" ] && [ -z "${GEMINI_API_KEY:-}" ]; then
  GEMINI_API_KEY=$(grep -E '^GEMINI_API_KEY=' "$ENV_FILE" | cut -d'=' -f2- | tr -d '[:space:]')
  export GEMINI_API_KEY
fi

# --- Validar GEMINI_API_KEY ---
GEMINI_API_KEY="$(echo -n "${GEMINI_API_KEY:-}" | tr -d '[:space:]')"

if [ -z "${GEMINI_API_KEY:-}" ]; then
  echo "ERRO: GEMINI_API_KEY nao configurada."
  echo "  1. Acesse: https://aistudio.google.com/apikey"
  echo "  2. Crie uma API key"
  echo "  3. Execute: export GEMINI_API_KEY='sua-key'"
  exit "$EXIT_DEP_MISSING"
fi

# --- Trap cleanup ---
OUTPUT_DIR_FOR_CLEANUP=""
cleanup_on_error() {
  local exit_code=$?
  cleanup
  if [ $exit_code -ne 0 ] && [ -n "$OUTPUT_DIR_FOR_CLEANUP" ] && [ -d "$OUTPUT_DIR_FOR_CLEANUP" ]; then
    if [ ! -f "$OUTPUT_DIR_FOR_CLEANUP/transcricao.md" ]; then
      rm -rf "$OUTPUT_DIR_FOR_CLEANUP"
    fi
  fi
  exit $exit_code
}
trap cleanup_on_error EXIT INT TERM HUP

# --- Detectar raiz do projeto ---
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

URL="${1:-}"

if [ -z "$URL" ]; then
  echo "ERRO: Nenhuma URL informada."
  exit "$EXIT_INPUT_ERROR"
fi

if [[ ! "$URL" =~ (youtube\.com|youtu\.be) ]]; then
  echo "ERRO: URL nao parece ser do YouTube."
  exit "$EXIT_INPUT_ERROR"
fi

# ============================================================
# DASHBOARD - Funcoes de UI
# ============================================================

# Cores ANSI
C_RESET="\033[0m"
C_BOLD="\033[1m"
C_DIM="\033[2m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_BLUE="\033[34m"
C_CYAN="\033[36m"
C_WHITE="\033[37m"
C_BG_DARK="\033[48;5;235m"
C_MAGENTA="\033[35m"
C_RED="\033[31m"

# Gemini Flash 2.5 pricing (por 1M tokens)
PRICE_INPUT_PER_M=0.15
PRICE_OUTPUT_PER_M=0.60

# Contadores de tokens e custo
TOTAL_INPUT_TOKENS=0
TOTAL_OUTPUT_TOKENS=0
TOTAL_COST=0
TOTAL_API_CALLS=0

# Estado das etapas: pending, running, done, error
STEP_1_STATUS="pending"
STEP_2_STATUS="pending"
STEP_3_STATUS="pending"
STEP_4_STATUS="pending"
STEP_5_STATUS="pending"

STEP_1_TIME=0
STEP_2_TIME=0
STEP_3_TIME=0
STEP_4_TIME=0
STEP_5_TIME=0

# Info do video (preenchido apos step 1)
DASH_TITLE="Aguardando..."
DASH_CHANNEL="-"
DASH_DURATION="-"
DASH_WORDS="-"
DASH_CHUNKS="-"
DASH_CHUNK_PROGRESS=""
DASH_OUTPUT_FILE="-"
DASH_FINAL_LINES="-"

# Numero de linhas do dashboard (para limpar)
DASH_LINES=0

step_icon() {
  local status="$1"
  case "$status" in
    pending) printf "${C_DIM}○${C_RESET}" ;;
    running) printf "${C_YELLOW}◉${C_RESET}" ;;
    done)    printf "${C_GREEN}●${C_RESET}" ;;
    error)   printf "${C_RED}✗${C_RESET}" ;;
  esac
}

step_label() {
  local status="$1"
  local label="$2"
  local time="$3"
  case "$status" in
    pending) printf "${C_DIM}%-30s${C_RESET}" "$label" ;;
    running) printf "${C_YELLOW}${C_BOLD}%-30s${C_RESET}" "$label" ;;
    done)    printf "${C_GREEN}%-30s${C_RESET} ${C_DIM}${time}s${C_RESET}" "$label" ;;
    error)   printf "${C_RED}%-30s${C_RESET}" "$label" ;;
  esac
}

format_cost() {
  awk "BEGIN { printf \"\$%.4f\", $1 }"
}

progress_bar() {
  local current="$1"
  local total="$2"
  local width=20
  if [ "$total" -eq 0 ]; then
    printf "[                    ]"
    return
  fi
  local filled=$(( current * width / total ))
  local empty=$(( width - filled ))
  printf "${C_GREEN}["
  for ((i=0; i<filled; i++)); do printf "█"; done
  for ((i=0; i<empty; i++)); do printf "${C_DIM}░${C_GREEN}"; done
  printf "]${C_RESET}"
}

draw_dashboard() {
  # Limpar linhas anteriores
  if [ "$DASH_LINES" -gt 0 ]; then
    printf "\033[%dA" "$DASH_LINES"
    for ((i=0; i<DASH_LINES; i++)); do
      printf "\033[2K\n"
    done
    printf "\033[%dA" "$DASH_LINES"
  fi

  local elapsed=$(( $(date +%s) - METRICS_START_TIME ))
  local mins=$(( elapsed / 60 ))
  local secs=$(( elapsed % 60 ))

  local lines=0

  # Header
  printf "${C_BOLD}${C_CYAN}╔══════════════════════════════════════════════════════════════════╗${C_RESET}\n"; ((lines++))
  printf "${C_BOLD}${C_CYAN}║${C_RESET}  ${C_BOLD}yt-text${C_RESET} ${C_DIM}— Transcricao YouTube + Gemini Flash 2.5${C_RESET}              ${C_CYAN}║${C_RESET}\n"; ((lines++))
  printf "${C_BOLD}${C_CYAN}╠══════════════════════════════════════════════════════════════════╣${C_RESET}\n"; ((lines++))

  # Video info
  local title_short="$DASH_TITLE"
  if [ ${#title_short} -gt 50 ]; then
    title_short="${title_short:0:47}..."
  fi
  printf "${C_CYAN}║${C_RESET} ${C_BOLD}Video:${C_RESET} %-57s ${C_CYAN}║${C_RESET}\n" "$title_short"; ((lines++))
  printf "${C_CYAN}║${C_RESET} ${C_DIM}Canal:${C_RESET} %-15s ${C_DIM}Duracao:${C_RESET} %-8s ${C_DIM}Palavras:${C_RESET} %-10s ${C_CYAN}║${C_RESET}\n" "$DASH_CHANNEL" "$DASH_DURATION" "$DASH_WORDS"; ((lines++))

  printf "${C_CYAN}╠══════════════════════════════════════════════════════════════════╣${C_RESET}\n"; ((lines++))

  # Steps
  printf "${C_CYAN}║${C_RESET} $(step_icon "$STEP_1_STATUS") $(step_label "$STEP_1_STATUS" "Metadados do video" "$STEP_1_TIME")                        ${C_CYAN}║${C_RESET}\n"; ((lines++))
  printf "${C_CYAN}║${C_RESET} $(step_icon "$STEP_2_STATUS") $(step_label "$STEP_2_STATUS" "Extrair legendas" "$STEP_2_TIME")                        ${C_CYAN}║${C_RESET}\n"; ((lines++))

  # Step 3 com progress bar de chunks
  if [ "$DASH_CHUNKS" != "-" ] && [ "$DASH_CHUNKS" != "1" ]; then
    local chunk_current="${DASH_CHUNK_CURRENT:-0}"
    local chunk_total="$DASH_CHUNKS"
    printf "${C_CYAN}║${C_RESET} $(step_icon "$STEP_3_STATUS") $(step_label "$STEP_3_STATUS" "Formatar transcricao" "$STEP_3_TIME")                        ${C_CYAN}║${C_RESET}\n"; ((lines++))
    if [ "$STEP_3_STATUS" = "running" ] || [ "$STEP_3_STATUS" = "done" ]; then
      printf "${C_CYAN}║${C_RESET}   $(progress_bar "$chunk_current" "$chunk_total") ${C_DIM}Parte ${chunk_current}/${chunk_total}${C_RESET} ${DASH_CHUNK_PROGRESS}              ${C_CYAN}║${C_RESET}\n"; ((lines++))
    fi
  else
    printf "${C_CYAN}║${C_RESET} $(step_icon "$STEP_3_STATUS") $(step_label "$STEP_3_STATUS" "Formatar transcricao" "$STEP_3_TIME")                        ${C_CYAN}║${C_RESET}\n"; ((lines++))
  fi

  printf "${C_CYAN}║${C_RESET} $(step_icon "$STEP_4_STATUS") $(step_label "$STEP_4_STATUS" "Resumo + Plano de Acao" "$STEP_4_TIME")                        ${C_CYAN}║${C_RESET}\n"; ((lines++))
  printf "${C_CYAN}║${C_RESET} $(step_icon "$STEP_5_STATUS") $(step_label "$STEP_5_STATUS" "Finalizar e salvar" "$STEP_5_TIME")                        ${C_CYAN}║${C_RESET}\n"; ((lines++))

  printf "${C_CYAN}╠══════════════════════════════════════════════════════════════════╣${C_RESET}\n"; ((lines++))

  # Tokens & Cost
  local cost_str
  cost_str=$(format_cost "$TOTAL_COST")
  local input_k=$(( TOTAL_INPUT_TOKENS / 1000 ))
  local output_k=$(( TOTAL_OUTPUT_TOKENS / 1000 ))
  local total_k=$(( (TOTAL_INPUT_TOKENS + TOTAL_OUTPUT_TOKENS) / 1000 ))

  printf "${C_CYAN}║${C_RESET} ${C_BOLD}Tokens${C_RESET}  ${C_DIM}Input:${C_RESET} ${C_WHITE}%6dk${C_RESET}  ${C_DIM}Output:${C_RESET} ${C_WHITE}%6dk${C_RESET}  ${C_DIM}Total:${C_RESET} ${C_WHITE}%6dk${C_RESET}  ${C_CYAN}║${C_RESET}\n" "$input_k" "$output_k" "$total_k"; ((lines++))
  printf "${C_CYAN}║${C_RESET} ${C_BOLD}Custo${C_RESET}   ${C_GREEN}${C_BOLD}%-10s${C_RESET}  ${C_DIM}(${TOTAL_API_CALLS} chamadas API)${C_RESET}                       ${C_CYAN}║${C_RESET}\n" "$cost_str"; ((lines++))
  printf "${C_CYAN}║${C_RESET} ${C_BOLD}Tempo${C_RESET}   ${C_WHITE}${mins}m ${secs}s${C_RESET}                                                  ${C_CYAN}║${C_RESET}\n"; ((lines++))

  printf "${C_CYAN}╚══════════════════════════════════════════════════════════════════╝${C_RESET}\n"; ((lines++))

  DASH_LINES=$lines
}

# ============================================================
# GEMINI API - com tracking de tokens
# ============================================================

# Arquivo temporario para respostas Gemini
GEMINI_RESPONSE_FILE=$(mktemp)
register_temp "$GEMINI_RESPONSE_FILE"

call_gemini_tracked() {
  local prompt_file="$1"
  local max_tokens="${2:-65536}"
  local timeout="${3:-300}"

  local payload
  payload=$(jq -n --rawfile prompt "$prompt_file" \
    --argjson max_tokens "$max_tokens" \
    '{
      "contents": [{"parts": [{"text": $prompt}]}],
      "generationConfig": {
        "temperature": 0.3,
        "maxOutputTokens": $max_tokens
      }
    }')

  curl -s -X POST \
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${GEMINI_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    --max-time "$timeout" \
    -o "$GEMINI_RESPONSE_FILE"

  # Extrair tokens da resposta
  local input_tokens output_tokens
  input_tokens=$(jq -r '.usageMetadata.promptTokenCount // 0' "$GEMINI_RESPONSE_FILE")
  output_tokens=$(jq -r '.usageMetadata.candidatesTokenCount // 0' "$GEMINI_RESPONSE_FILE")

  # Acumular (no escopo global, sem subshell)
  TOTAL_INPUT_TOKENS=$(( TOTAL_INPUT_TOKENS + input_tokens ))
  TOTAL_OUTPUT_TOKENS=$(( TOTAL_OUTPUT_TOKENS + output_tokens ))
  TOTAL_API_CALLS=$(( TOTAL_API_CALLS + 1 ))

  # Calcular custo
  local call_cost
  call_cost=$(awk "BEGIN { printf \"%.6f\", ($input_tokens * $PRICE_INPUT_PER_M / 1000000) + ($output_tokens * $PRICE_OUTPUT_PER_M / 1000000) }")
  TOTAL_COST=$(awk "BEGIN { printf \"%.6f\", $TOTAL_COST + $call_cost }")
}

# Extrair texto da ultima resposta Gemini
gemini_text() {
  jq -r '.candidates[0].content.parts[0].text // empty' "$GEMINI_RESPONSE_FILE"
}

# ============================================================
# EXECUCAO PRINCIPAL
# ============================================================

metrics_start

# Desenho inicial do dashboard
draw_dashboard

# --- STEP 1: Metadados ---
STEP_1_STATUS="running"
draw_dashboard

STEP_1_START=$(date +%s)
VIDEO_JSON=$(yt-dlp --dump-json --no-download "$URL" 2>/dev/null)
VIDEO_TITLE=$(echo "$VIDEO_JSON" | jq -r '.title // "sem-titulo"')
VIDEO_ID=$(echo "$VIDEO_JSON" | jq -r '.id // "unknown"')
VIDEO_DURATION=$(echo "$VIDEO_JSON" | jq -r '.duration // 0')
VIDEO_CHANNEL=$(echo "$VIDEO_JSON" | jq -r '.channel // "desconhecido"')
VIDEO_UPLOAD_DATE=$(echo "$VIDEO_JSON" | jq -r '.upload_date // "00000000"')
VIDEO_LANG=$(echo "$VIDEO_JSON" | jq -r '.language // "und"')

SLUG=$(echo "$VIDEO_TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-//' | sed 's/-$//' | cut -c1-80)
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
OUTPUT_DIR="${OUTPUT_ROOT:-./outputs/videos}/${SLUG}-${TIMESTAMP}"
OUTPUT_DIR_FOR_CLEANUP="$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# shellcheck disable=SC2034
LOG_FILE="$OUTPUT_DIR/process.log"
log_info "Video: $VIDEO_TITLE (ID: $VIDEO_ID)"

DASH_TITLE="$VIDEO_TITLE"
DASH_CHANNEL="$VIDEO_CHANNEL"
DASH_DURATION="$((VIDEO_DURATION / 60))min"

STEP_1_TIME=$(( $(date +%s) - STEP_1_START ))
STEP_1_STATUS="done"
draw_dashboard

# --- STEP 2: Legendas ---
STEP_2_STATUS="running"
draw_dashboard

STEP_2_START=$(date +%s)
SUBS_DIR="$OUTPUT_DIR/subs"
mkdir -p "$SUBS_DIR"
register_temp "$SUBS_DIR"

# Normalizar idioma: pt-BR -> pt, en-US -> en (yt-dlp usa codigos curtos)
LANG_SHORT="${VIDEO_LANG%%-*}"
if [ "$LANG_SHORT" = "und" ] || [ -z "$LANG_SHORT" ]; then
  LANG_SHORT="pt"
fi

# Prioridade 1: Transcricao automatica (auto-captions) no idioma do video
# Esta e a TRANSCRICAO do YouTube, nao legendas manuais
yt-dlp --write-auto-sub --sub-lang "$LANG_SHORT" --skip-download \
  --sub-format vtt --output "$SUBS_DIR/%(id)s" "$URL" 2>/dev/null || true

# Prioridade 2: Transcricao automatica em ingles (fallback)
if [ -z "$(find "$SUBS_DIR" -name "*.vtt" 2>/dev/null | head -1)" ] && [ "$LANG_SHORT" != "en" ]; then
  yt-dlp --write-auto-sub --sub-lang en --skip-download \
    --sub-format vtt --output "$SUBS_DIR/%(id)s" "$URL" 2>/dev/null || true
fi

# Prioridade 3: Legenda manual (se existir)
if [ -z "$(find "$SUBS_DIR" -name "*.vtt" 2>/dev/null | head -1)" ]; then
  yt-dlp --write-sub --sub-lang "$LANG_SHORT,en" --skip-download \
    --sub-format vtt --output "$SUBS_DIR/%(id)s" "$URL" 2>/dev/null || true
fi

SUBTITLE_FILE=$(find "$SUBS_DIR" -name "*.vtt" 2>/dev/null | head -1)

if [ -z "$SUBTITLE_FILE" ]; then
  STEP_2_STATUS="error"
  draw_dashboard
  echo ""
  echo "ERRO: Nenhuma legenda encontrada para este video."
  exit "$EXIT_PROCESSING_ERROR"
fi

RAW_TEXT="$OUTPUT_DIR/transcricao-bruta.txt"
sed '/^WEBVTT/d; /^Kind:/d; /^Language:/d; /^$/d; /^[0-9][0-9]:[0-9][0-9]/d; /-->/d; s/<[^>]*>//g' \
  "$SUBTITLE_FILE" | \
  awk '!seen[$0]++ || NF==0' | \
  sed '/^$/N;/^\n$/d' > "$RAW_TEXT"

RAW_WORDS=$(wc -w < "$RAW_TEXT" | tr -d ' ')
DASH_WORDS="$RAW_WORDS"

STEP_2_TIME=$(( $(date +%s) - STEP_2_START ))
STEP_2_STATUS="done"
draw_dashboard

# --- STEP 3: Formatar com Gemini (chunking) ---
STEP_3_STATUS="running"

# Instrucao de traducao (se idioma nativo nao for portugues)
TRANSLATE_INSTRUCTION=""
if [[ "$VIDEO_LANG" != "pt" && "$VIDEO_LANG" != "pt-BR" && "$VIDEO_LANG" != "pt-br" ]]; then
  TRANSLATE_INSTRUCTION="IMPORTANTE: O conteudo original esta em ${VIDEO_LANG}. Voce DEVE TRADUZIR todo o conteudo para PORTUGUES BRASILEIRO (pt-BR) mantendo o sentido, tom e estilo do autor. A traducao deve soar natural, nao literal."
fi

CHUNK_THRESHOLD=6000
FORMATTED_CHUNKS_DIR="$OUTPUT_DIR/chunks"
mkdir -p "$FORMATTED_CHUNKS_DIR"
register_temp "$FORMATTED_CHUNKS_DIR"

STEP_3_START=$(date +%s)

if [ "$RAW_WORDS" -gt "$CHUNK_THRESHOLD" ]; then
  NUM_CHUNKS=$(( (RAW_WORDS + CHUNK_THRESHOLD - 1) / CHUNK_THRESHOLD ))
  LINES_PER_CHUNK=$(( $(wc -l < "$RAW_TEXT" | tr -d ' ') / NUM_CHUNKS + 1 ))
  DASH_CHUNKS="$NUM_CHUNKS"
  DASH_CHUNK_CURRENT=0
  draw_dashboard

  # Dividir em chunks com awk (macOS split tem bugs com paths longos)
  awk -v lines="$LINES_PER_CHUNK" -v prefix="$FORMATTED_CHUNKS_DIR/chunk_" '
    BEGIN { file_num = 1; line_count = 0; fname = sprintf("%s%03d", prefix, file_num) }
    {
      if (line_count >= lines) {
        close(fname)
        file_num++
        fname = sprintf("%s%03d", prefix, file_num)
        line_count = 0
      }
      print > fname
      line_count++
    }
  ' "$RAW_TEXT"

  CHUNK_NUM=0
  TOTAL_CHUNKS=$(ls "$FORMATTED_CHUNKS_DIR"/chunk_* 2>/dev/null | wc -l | tr -d ' ')

  for CHUNK_FILE in "$FORMATTED_CHUNKS_DIR"/chunk_*; do
    CHUNK_NUM=$((CHUNK_NUM + 1))
    DASH_CHUNK_CURRENT=$CHUNK_NUM
    DASH_CHUNK_PROGRESS=""
    draw_dashboard

    CHUNK_PROMPT="$FORMATTED_CHUNKS_DIR/prompt_${CHUNK_NUM}.tmp"
    {
      echo "Voce e um editor de texto especializado. Recebeu a PARTE $CHUNK_NUM de $TOTAL_CHUNKS da transcricao bruta de um video do YouTube."
      echo ""
      echo "TITULO DO VIDEO: $VIDEO_TITLE"
      echo "CANAL: $VIDEO_CHANNEL"
      if [ -n "$TRANSLATE_INSTRUCTION" ]; then
        echo ""
        echo "$TRANSLATE_INSTRUCTION"
      fi
      cat <<'CHUNK_BODY'

INSTRUCOES:
1. FORMATAR A TRANSCRICAO desta parte:
   - Traduza para portugues brasileiro (se nao estiver em portugues)
   - Corrija erros de portugues (acentuacao, concordancia, pontuacao)
   - Divida em paragrafos logicos
   - Adicione subtitulos (###) para organizar o conteudo por temas
   - Mantenha o conteudo original COMPLETO - NAO resuma, NAO omita nada
   - Use markdown formatado
2. NAO adicione titulo principal (# ), resumo ou plano de acao - apenas formate o texto desta parte.
3. Comece direto com o conteudo formatado.
4. TODO o output DEVE estar em PORTUGUES BRASILEIRO.

TRANSCRICAO BRUTA:
CHUNK_BODY
      cat "$CHUNK_FILE"
    } > "$CHUNK_PROMPT"

    call_gemini_tracked "$CHUNK_PROMPT" 65536 300
    CHUNK_RESULT=$(gemini_text)
    if [ -n "$CHUNK_RESULT" ]; then
      echo "$CHUNK_RESULT" > "$FORMATTED_CHUNKS_DIR/formatted_${CHUNK_NUM}.md"
      DASH_CHUNK_PROGRESS="${C_GREEN}OK${C_RESET}"
    else
      cat "$CHUNK_FILE" > "$FORMATTED_CHUNKS_DIR/formatted_${CHUNK_NUM}.md"
      DASH_CHUNK_PROGRESS="${C_RED}fallback${C_RESET}"
    fi
    draw_dashboard
  done

  # Combinar chunks
  COMBINED_FILE="$FORMATTED_CHUNKS_DIR/combined.md"
  for FCHUNK in $(ls "$FORMATTED_CHUNKS_DIR"/formatted_*.md | sort -V); do
    cat "$FCHUNK" >> "$COMBINED_FILE"
    echo "" >> "$COMBINED_FILE"
    echo "" >> "$COMBINED_FILE"
  done

  STEP_3_TIME=$(( $(date +%s) - STEP_3_START ))
  STEP_3_STATUS="done"
  draw_dashboard

  # --- STEP 4: Resumo + Plano ---
  STEP_4_STATUS="running"
  STEP_4_START=$(date +%s)
  draw_dashboard

  SUMMARY_PROMPT="$FORMATTED_CHUNKS_DIR/summary_prompt.tmp"

  {
    echo "Voce e um escritor especializado em condensar conteudos longos em resumos densos e completos."
    echo "Sua habilidade e transformar horas de conteudo em textos curtos que capturam TODA a essencia, como um livro condensado."
    echo "TODO o output DEVE estar em PORTUGUES BRASILEIRO (pt-BR)."
    echo ""
    echo "TITULO: $VIDEO_TITLE"
    echo "CANAL: $VIDEO_CHANNEL"
    echo "DURACAO: $((VIDEO_DURATION / 60)) minutos"
    if [ -n "$TRANSLATE_INSTRUCTION" ]; then
      echo ""
      echo "$TRANSLATE_INSTRUCTION"
    fi
    cat <<'SUMMARY_BODY'

TAREFA: Gere DUAS secoes a partir da transcricao completa abaixo.

---

## Resumo

Escreva um RESUMO NARRATIVO DENSO do conteudo. NAO use bullets soltos.

Regras:
- Escreva em paragrafos fluidos e bem conectados, como um artigo ou capitulo de livro
- O resumo deve ter entre 10-15% do tamanho da transcricao original
- Organize por SECOES TEMATICAS com subtitulos (### Subtitulo)
- Cada secao deve cobrir um bloco tematico do video
- Capture: conceitos-chave, exemplos concretos citados, numeros/dados mencionados, historias contadas, ferramentas/recursos recomendados
- O leitor que ler APENAS o resumo deve entender o conteudo completo sem precisar assistir o video
- Use **negrito** para termos e conceitos importantes
- Mantenha o tom e estilo do autor original
- Ao final do resumo, inclua uma subsecao "### Citacoes e Insights Marcantes" com 5-8 frases impactantes ditas pelo autor (entre aspas)

---

## Plano de Acao

Crie um plano de acao ESTRUTURADO e PRATICO baseado no conteudo.

Formato obrigatorio:

### Acoes Imediatas (fazer hoje)
- [ ] **Acao concreta** — Descricao breve de como executar

### Acoes de Curto Prazo (proximos 7 dias)
- [ ] **Acao concreta** — Descricao breve de como executar

### Acoes de Medio Prazo (proximo mes)
- [ ] **Acao concreta** — Descricao breve de como executar

### Recursos Mencionados
| Recurso | O que e | Link/Como acessar |
|---------|---------|-------------------|
| Nome | Descricao | URL ou instrucao |

Regras:
- Cada acao deve ser ESPECIFICA e EXECUTAVEL (nao generica)
- Inclua ferramentas, comandos ou passos concretos mencionados no video
- Se o autor mencionou links, sites ou ferramentas, liste na tabela de recursos

---

TRANSCRICAO COMPLETA:
SUMMARY_BODY
    cat "$COMBINED_FILE"
  } > "$SUMMARY_PROMPT"

  call_gemini_tracked "$SUMMARY_PROMPT" 16384 300
  SUMMARY_RESULT=$(gemini_text)

  # Montar arquivo final
  {
    echo "# $VIDEO_TITLE"
    echo ""
    echo "> Canal: $VIDEO_CHANNEL | Duracao: $((VIDEO_DURATION / 60))min | Data: $VIDEO_UPLOAD_DATE"
    echo ""
    echo "<!-- VIDEO: https://www.youtube.com/watch?v=$VIDEO_ID -->"
    echo ""
    echo "## Transcricao"
    echo ""
    cat "$COMBINED_FILE"
    echo ""
    if [ -n "$SUMMARY_RESULT" ]; then
      echo "$SUMMARY_RESULT"
    else
      echo "## Resumo"
      echo ""
      echo "_Nao foi possivel gerar o resumo automaticamente._"
      echo ""
      echo "## Plano de Acao"
      echo ""
      echo "- [ ] Revisar a transcricao e extrair pontos principais"
    fi
  } > "$OUTPUT_DIR/transcricao.md"

  STEP_4_TIME=$(( $(date +%s) - STEP_4_START ))
  STEP_4_STATUS="done"
  draw_dashboard

else
  # Video curto - chamada unica
  DASH_CHUNKS="1"
  draw_dashboard

  PROMPT_FILE="$OUTPUT_DIR/prompt.tmp"
  register_temp "$PROMPT_FILE"

  {
    echo "Voce e um editor de texto especializado. Recebeu a transcricao bruta de um video do YouTube."
    echo "TODO o output DEVE estar em PORTUGUES BRASILEIRO (pt-BR)."
    echo ""
    echo "TITULO DO VIDEO: $VIDEO_TITLE"
    echo "CANAL: $VIDEO_CHANNEL"
    echo ""
    echo "VIDEO URL: https://www.youtube.com/watch?v=$VIDEO_ID"
    if [ -n "$TRANSLATE_INSTRUCTION" ]; then
      echo ""
      echo "$TRANSLATE_INSTRUCTION"
    fi
    cat <<'PROMPT_BODY'

INSTRUCOES:
1. FORMATAR A TRANSCRICAO:
   - Traduza para portugues brasileiro (se nao estiver em portugues)
   - Corrija erros de portugues (acentuacao, concordancia, pontuacao)
   - Divida em paragrafos logicos
   - Adicione titulos e subtitulos (## e ###) para organizar o conteudo por temas
   - Mantenha o conteudo original COMPLETO - NAO resuma, NAO omita nada
   - Use markdown formatado

2. GERAR RESUMO NARRATIVO DENSO:
   - Escreva em paragrafos fluidos e bem conectados (NAO bullets soltos)
   - Organize por secoes tematicas com subtitulos (### Subtitulo)
   - Capture conceitos-chave, exemplos, numeros, historias, ferramentas
   - Use **negrito** para termos importantes
   - Ao final, inclua "### Citacoes e Insights Marcantes" com 3-5 frases do autor

3. GERAR PLANO DE ACAO ESTRUTURADO:
   - Divida em: "### Acoes Imediatas", "### Acoes de Curto Prazo", "### Acoes de Medio Prazo"
   - Cada acao: - [ ] **Acao** — Descricao de como executar
   - Se houver recursos mencionados, inclua tabela "### Recursos Mencionados"

FORMATO DO OUTPUT (siga exatamente):

# {Titulo do Video}

> Canal: {canal} | Duracao: {duracao} | Data: {data}

<!-- VIDEO: {video_url do campo acima} -->

## Transcricao

{transcricao formatada com titulos por secao}

## Resumo

{resumo narrativo denso em paragrafos, com subsecoes tematicas}

## Plano de Acao

{plano estruturado por horizonte temporal}

TRANSCRICAO BRUTA:
PROMPT_BODY
    cat "$RAW_TEXT"
  } > "$PROMPT_FILE"

  call_gemini_tracked "$PROMPT_FILE" 65536 300
  FORMATTED_TEXT=$(gemini_text)

  if [ -z "$FORMATTED_TEXT" ]; then
    {
      echo "# $VIDEO_TITLE"
      echo ""
      echo "> Canal: $VIDEO_CHANNEL | Duracao: $((VIDEO_DURATION / 60))min"
      echo ""
      echo "<!-- VIDEO: https://www.youtube.com/watch?v=$VIDEO_ID -->"
      echo ""
      echo "## Transcricao (bruta - formatacao Gemini falhou)"
      echo ""
      cat "$RAW_TEXT"
    } > "$OUTPUT_DIR/transcricao.md"
  else
    echo "$FORMATTED_TEXT" > "$OUTPUT_DIR/transcricao.md"
  fi

  STEP_3_TIME=$(( $(date +%s) - STEP_3_START ))
  STEP_3_STATUS="done"
  STEP_4_STATUS="done"
  STEP_4_TIME=0
  draw_dashboard
fi

# --- STEP 5: Finalizar ---
STEP_5_STATUS="running"
STEP_5_START=$(date +%s)
draw_dashboard

PROCESSING_TIME=$(( $(date +%s) - METRICS_START_TIME ))

DASH_OUTPUT_FILE="$OUTPUT_DIR/transcricao.md"
DASH_FINAL_LINES=$(wc -l < "$OUTPUT_DIR/transcricao.md" | tr -d ' ')

write_metadata "$OUTPUT_DIR/metadata.json" \
  "source=$URL" \
  "service=yt-text" \
  "video_id=$VIDEO_ID" \
  "video_title=$VIDEO_TITLE" \
  "channel=$VIDEO_CHANNEL" \
  "upload_date=$VIDEO_UPLOAD_DATE" \
  "duration_seconds=$VIDEO_DURATION" \
  "raw_word_count=$RAW_WORDS" \
  "source_language=$VIDEO_LANG" \
  "output_language=pt-BR" \
  "processing_time_seconds=$PROCESSING_TIME" \
  "gemini_model=gemini-2.5-flash" \
  "total_input_tokens=$TOTAL_INPUT_TOKENS" \
  "total_output_tokens=$TOTAL_OUTPUT_TOKENS" \
  "total_api_calls=$TOTAL_API_CALLS" \
  "total_cost_usd=$TOTAL_COST"

# Limpar temporarios
rm -rf "$SUBS_DIR" 2>/dev/null || true
rm -f "$OUTPUT_DIR/prompt.tmp" 2>/dev/null || true
rm -rf "$FORMATTED_CHUNKS_DIR" 2>/dev/null || true

write_metrics "$OUTPUT_DIR/metrics.json" \
  "metadata=$STEP_1_TIME" \
  "captions=$STEP_2_TIME" \
  "gemini=$STEP_3_TIME" \
  "resumo=$STEP_4_TIME" \
  "finalizacao=0"

STEP_5_TIME=$(( $(date +%s) - STEP_5_START ))
STEP_5_STATUS="done"
draw_dashboard

# --- RESULTADO FINAL ---
echo ""
printf "${C_BOLD}${C_GREEN}╔══════════════════════════════════════════════════════════════════╗${C_RESET}\n"
printf "${C_GREEN}║${C_RESET}  ${C_BOLD}${C_GREEN}✓ TRANSCRICAO COMPLETA${C_RESET}                                         ${C_GREEN}║${C_RESET}\n"
printf "${C_GREEN}╠══════════════════════════════════════════════════════════════════╣${C_RESET}\n"
printf "${C_GREEN}║${C_RESET}                                                                  ${C_GREEN}║${C_RESET}\n"
printf "${C_GREEN}║${C_RESET}  ${C_BOLD}Output:${C_RESET} %-55s ${C_GREEN}║${C_RESET}\n" "$OUTPUT_DIR/"
printf "${C_GREEN}║${C_RESET}  ${C_DIM}transcricao.md${C_RESET}  ${C_WHITE}${DASH_FINAL_LINES} linhas${C_RESET}                                    ${C_GREEN}║${C_RESET}\n"
printf "${C_GREEN}║${C_RESET}                                                                  ${C_GREEN}║${C_RESET}\n"

# Custo final
local_cost=$(format_cost "$TOTAL_COST")
local_input_k=$(( TOTAL_INPUT_TOKENS / 1000 ))
local_output_k=$(( TOTAL_OUTPUT_TOKENS / 1000 ))
local_total_k=$(( (TOTAL_INPUT_TOKENS + TOTAL_OUTPUT_TOKENS) / 1000 ))

printf "${C_GREEN}║${C_RESET}  ${C_BOLD}Custo total:${C_RESET}  ${C_GREEN}${C_BOLD}${local_cost}${C_RESET}                                       ${C_GREEN}║${C_RESET}\n"
printf "${C_GREEN}║${C_RESET}  ${C_DIM}Tokens: ${local_input_k}k input + ${local_output_k}k output = ${local_total_k}k total${C_RESET}               ${C_GREEN}║${C_RESET}\n"
printf "${C_GREEN}║${C_RESET}  ${C_DIM}API calls: ${TOTAL_API_CALLS} | Tempo: ${PROCESSING_TIME}s${C_RESET}                                ${C_GREEN}║${C_RESET}\n"
printf "${C_GREEN}║${C_RESET}                                                                  ${C_GREEN}║${C_RESET}\n"
printf "${C_GREEN}╚══════════════════════════════════════════════════════════════════╝${C_RESET}\n"

log_info "Processamento concluido com sucesso"
