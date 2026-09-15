#!/bin/bash
# Transcrever video/audio com Whisper (otimizado)
# Converte para mono 16kHz + 2x speed antes de transcrever

set -euo pipefail

# --- Help inline (v1.12) ---
show_help() {
  cat <<'HELP'
=== Transcrever - Transcricao local com Whisper ===

Uso: transcrever.sh <arquivo> [idioma] [modelo] [velocidade]

Parametros:
  arquivo     Caminho do audio/video (obrigatorio)
  idioma      pt (padrao), en, es, etc.
  modelo      tiny, base, small, medium (padrao), large
  velocidade  1x, 2x (padrao), 3x, 4x

Modelos:
  tiny    (39MB)  - Muito rapido, baixa qualidade PT
  base    (74MB)  - Rapido, qualidade razoavel
  small   (244MB) - Moderado, boa qualidade
  medium  (769MB) - Lento, muito boa qualidade [PADRAO]
  large   (1.5GB) - Muito lento, excelente qualidade

Formatos aceitos:
  mp3, mp4, m4a, wav, webm, ogg, flac, avi, mkv, mov, aac, wma

Exemplos:
  transcrever.sh video.mp4                     # pt, medium, 2x
  transcrever.sh podcast.mp3 en large 1        # ingles, large, sem aceleracao
HELP
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  show_help
  exit 0
fi

# --- Source lib compartilhada (v1.5) ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../../_shared/lib.sh
source "$SCRIPT_DIR/../../_shared/lib.sh"

# --- Python path portavel (v1.1) ---
PYTHON3=$(command -v python3 || true)
if [ -z "$PYTHON3" ]; then
  echo "ERRO: python3 nao encontrado no PATH."
  echo "  Instale Python 3.9+ e tente novamente."
  exit "$EXIT_DEP_MISSING"
fi
PIP_USER_BIN=$("$PYTHON3" -m site --user-base 2>/dev/null)/bin
BREW_PREFIX=$(brew --prefix 2>/dev/null || echo "/usr/local")
export PATH="$PIP_USER_BIN:$BREW_PREFIX/bin:$PATH"

# --- Validacao de dependencias (v1.3) ---
check_dependency ffmpeg "brew install ffmpeg"
check_dependency whisper "pip install openai-whisper"

# --- Trap cleanup (v1.2) ---
trap cleanup EXIT INT TERM HUP

# --- Detectar raiz do projeto ---
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

INPUT="${1:-}"
LANG="${2:-pt}"
MODEL="${3:-medium}"
SPEED="${4:-2}"
OUTPUT_DIR="${OUTPUT_ROOT:-./outputs/transcriptions}"

# --- Validacao de input (v1.4 + v1.7) ---
TRANSCREVER_FORMATS="mp3 mp4 m4a wav webm ogg flac avi mkv mov aac wma"
if [ -z "$INPUT" ]; then
  echo "ERRO: Nenhum arquivo informado."
  echo "  Uso: transcrever.sh <arquivo> [idioma] [modelo] [velocidade]"
  echo "  Execute transcrever.sh --help para mais informacoes."
  exit "$EXIT_INPUT_ERROR"
fi
validate_input "$INPUT" 2048 "$TRANSCREVER_FORMATS"

BASENAME=$(basename "$INPUT" | sed 's/\.[^.]*$//')
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
SLUG="${BASENAME}-${TIMESTAMP}"
WORK_DIR="$OUTPUT_DIR/$SLUG"
mkdir -p "$WORK_DIR"

# --- Logging (v1.9) ---
# shellcheck disable=SC2034
LOG_FILE="$WORK_DIR/process.log"
metrics_start

log_info "Inicio do processamento"
log_info "Input: $INPUT"
log_info "Parametros: idioma=$LANG modelo=$MODEL velocidade=${SPEED}x"
log_info "Versao ffmpeg: $(ffmpeg -version 2>/dev/null | head -1)"
log_info "Versao whisper: $(whisper --version 2>/dev/null || echo 'desconhecida')"

echo "=== Transcricao Whisper ==="
echo "Arquivo: $INPUT"
echo "Idioma: $LANG"
echo "Modelo: $MODEL"
echo "Velocidade: ${SPEED}x"
echo "Saida: $WORK_DIR"
echo ""

# Passo 1: Converter para mono 16kHz + acelerar audio
MONO_FILE="$WORK_DIR/audio-mono.wav"
register_temp "$MONO_FILE"

metrics_step_start "conversao"
show_progress 1 2 "Convertendo para mono 16kHz + ${SPEED}x..."

# atempo aceita valores entre 0.5 e 2.0, para >2x encadear filtros
if [ "$SPEED" = "1" ]; then
  ATEMPO_FILTER=""
elif [ "$SPEED" = "2" ]; then
  ATEMPO_FILTER="-filter:a atempo=2.0"
elif [ "$SPEED" = "3" ]; then
  ATEMPO_FILTER="-filter:a atempo=2.0,atempo=1.5"
elif [ "$SPEED" = "4" ]; then
  ATEMPO_FILTER="-filter:a atempo=2.0,atempo=2.0"
else
  ATEMPO_FILTER="-filter:a atempo=2.0"
fi

# shellcheck disable=SC2086
ffmpeg -y -i "$INPUT" $ATEMPO_FILTER -ac 1 -ar 16000 -acodec pcm_s16le "$MONO_FILE" -loglevel warning
metrics_step_end "conversao"

ORIGINAL_SIZE=$(filesize "$INPUT")
MONO_SIZE=$(filesize "$MONO_FILE")
echo "Original: $(echo "scale=1; $ORIGINAL_SIZE/1048576" | bc)MB -> Processado: $(echo "scale=1; $MONO_SIZE/1048576" | bc)MB"
echo ""

# Passo 2: Transcrever com Whisper
metrics_step_start "transcricao"
show_progress 2 2 "Transcrevendo com modelo $MODEL..."
whisper "$MONO_FILE" \
  --language "$LANG" \
  --model "$MODEL" \
  --output_dir "$WORK_DIR" \
  --output_format all \
  --verbose False
metrics_step_end "transcricao"

# Renomear outputs
for ext in txt srt vtt json tsv; do
  if [ -f "$WORK_DIR/audio-mono.$ext" ]; then
    mv "$WORK_DIR/audio-mono.$ext" "$WORK_DIR/$BASENAME.$ext"
  fi
done

# --- Preview curto (v1.6) ---
TOTAL_LINES=$(wc -l < "$WORK_DIR/$BASENAME.txt" | tr -d ' ')
TOTAL_WORDS=$(wc -w < "$WORK_DIR/$BASENAME.txt" | tr -d ' ')

echo ""
echo "=== Transcricao completa ==="
echo "Arquivo: $WORK_DIR/$BASENAME.txt ($TOTAL_LINES linhas, $TOTAL_WORDS palavras)"
echo ""
echo "Preview (10 primeiras linhas):"
echo "---"
head -10 "$WORK_DIR/$BASENAME.txt"
if [ "$TOTAL_LINES" -gt 10 ]; then
  echo "... ($TOTAL_LINES linhas no total)"
fi
echo "---"

# --- Metadata JSON (v1.8) ---
DURATION=$(ffprobe -v quiet -show_entries format=duration -of csv=p=0 "$INPUT" 2>/dev/null | cut -d. -f1 || echo "0")
PROCESSING_TIME=$(( $(date +%s) - METRICS_START_TIME ))

write_metadata "$WORK_DIR/metadata.json" \
  "source=$(basename "$INPUT")" \
  "service=transcrever" \
  "duration_seconds=${DURATION:-0}" \
  "model=$MODEL" \
  "language=$LANG" \
  "speed=$SPEED" \
  "word_count=$TOTAL_WORDS" \
  "processing_time_seconds=$PROCESSING_TIME" \
  "file_size_bytes=$ORIGINAL_SIZE"

# --- Metrics JSON (v1.9) ---
CONV_DUR="${STEP_DURATION_conversao:-0}"
TRANS_DUR="${STEP_DURATION_transcricao:-0}"
write_metrics "$WORK_DIR/metrics.json" \
  "conversao=$CONV_DUR" \
  "transcricao=$TRANS_DUR"

log_info "Processamento concluido com sucesso"
