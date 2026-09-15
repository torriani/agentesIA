#!/bin/bash
# Converte ebook (ePub, MOBI, AZW, PDF) para Markdown formatado
# Usa Pandoc para ePub, Calibre + Pandoc para MOBI/AZW, pdftotext/Pandoc para PDF

set -euo pipefail

# --- Help inline (v1.12) ---
show_help() {
  cat <<'HELP'
=== Ebook to Markdown - Conversor de ebooks para MD ===

Uso: ebook-to-md.sh <arquivo>

Parametros:
  arquivo     Caminho do ebook (obrigatorio)

Formatos suportados:
  epub        Conversao direta via Pandoc
  mobi/azw    Calibre -> ePub -> Pandoc
  azw3/kfx    Calibre -> ePub -> Pandoc
  pdf         pdftotext (ou Calibre como fallback)
  txt         Copia direta
  html/htm    Pandoc direto

Dependencias:
  pandoc          brew install pandoc (obrigatorio)
  ebook-convert   brew install calibre (para MOBI/AZW)
  pdftotext       brew install poppler (para PDF)

Exemplos:
  ebook-to-md.sh livro.epub
  ebook-to-md.sh manual.pdf
  ebook-to-md.sh /pasta/curso.mobi
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

# --- Path portavel (v1.1) ---
BREW_PREFIX=$(brew --prefix 2>/dev/null || echo "/usr/local")
export PATH="$BREW_PREFIX/bin:$PATH"

# --- Validacao de dependencias (v1.3) ---
check_dependency pandoc "brew install pandoc"

# --- Trap cleanup (v1.2) ---
trap cleanup EXIT INT TERM HUP

# --- Detectar raiz do projeto ---
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"

INPUT="${1:-}"
OUTPUT_BASE="${OUTPUT_ROOT:-./outputs/livros}"

# --- Validacao de input (v1.4 + v1.7) ---
EBOOK_FORMATS="epub mobi azw azw3 kfx pdf html htm txt"
if [ -z "$INPUT" ]; then
  echo "ERRO: Nenhum arquivo informado."
  echo "  Uso: ebook-to-md.sh <arquivo>"
  echo "  Execute ebook-to-md.sh --help para mais informacoes."
  exit "$EXIT_INPUT_ERROR"
fi
validate_input "$INPUT" 500 "$EBOOK_FORMATS"

# Extrair nome do livro (sem extensao) e criar slug
BASENAME=$(basename "$INPUT" | sed 's/\.[^.]*$//')
SLUG=$(echo "$BASENAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9áàâãéèêíïóôõúüç_-]/-/g' | sed 's/--*/-/g' | sed 's/^-//;s/-$//')
EXT="${INPUT##*.}"
EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')

WORK_DIR="$OUTPUT_BASE/$SLUG"
mkdir -p "$WORK_DIR"

# --- Logging (v1.9) ---
# shellcheck disable=SC2034
LOG_FILE="$WORK_DIR/process.log"
metrics_start

log_info "Inicio do processamento"
log_info "Input: $INPUT"
log_info "Formato: $EXT_LOWER"
log_info "Versao pandoc: $(pandoc --version 2>/dev/null | head -1)"

echo "=== Ebook -> Markdown ==="
echo "Arquivo: $INPUT"
echo "Formato: $EXT_LOWER"
echo "Saida: $WORK_DIR/"
echo ""

# Validar dependencias opcionais por formato (v1.3)
case "$EXT_LOWER" in
  mobi|azw|azw3|kfx)
    check_dependency ebook-convert "brew install calibre"
    ;;
  pdf)
    check_dependency pdftotext "brew install poppler"
    ;;
esac

# --- Metadata: extrair titulo/autor se possivel (v1.8) ---
META_TITLE=""
META_AUTHOR=""
META_PAGES=""
if command -v ebook-meta &>/dev/null; then
  META_TITLE=$(ebook-meta "$INPUT" 2>/dev/null | grep "^Title" | cut -d: -f2- | xargs 2>/dev/null || true)
  META_AUTHOR=$(ebook-meta "$INPUT" 2>/dev/null | grep "^Author" | cut -d: -f2- | xargs 2>/dev/null || true)
fi
if [ "$EXT_LOWER" = "pdf" ] && command -v pdfinfo &>/dev/null; then
  META_PAGES=$(pdfinfo "$INPUT" 2>/dev/null | grep "^Pages" | awk '{print $2}' || true)
fi

metrics_step_start "conversao"

case "$EXT_LOWER" in
  epub)
    show_progress 1 1 "Convertendo ePub -> Markdown com Pandoc..."
    pandoc "$INPUT" -f epub -t markdown --wrap=none -o "$WORK_DIR/$SLUG.md"
    ;;

  mobi|azw|azw3|kfx)
    TEMP_EPUB="$WORK_DIR/_temp.epub"
    register_temp "$TEMP_EPUB"
    show_progress 1 2 "Convertendo $EXT_LOWER -> ePub com Calibre..."
    ebook-convert "$INPUT" "$TEMP_EPUB" --no-default-epub-cover 2>/dev/null
    show_progress 2 2 "Convertendo ePub -> Markdown com Pandoc..."
    pandoc "$TEMP_EPUB" -f epub -t markdown --wrap=none -o "$WORK_DIR/$SLUG.md"
    ;;

  pdf)
    RAW_TXT="$WORK_DIR/_raw.txt"
    register_temp "$RAW_TXT"
    show_progress 1 2 "Extraindo texto do PDF com pdftotext..."
    pdftotext -layout "$INPUT" "$RAW_TXT"

    CHARS=$(wc -c < "$RAW_TXT" | tr -d ' ')
    if [ "$CHARS" -lt 500 ]; then
      echo "AVISO: PDF escaneado detectado (apenas $CHARS caracteres extraidos)."
      echo "  Instale OCRmyPDF para processar scans: pip install ocrmypdf"
      echo "Tentando com Calibre como fallback..."
      TEMP_HTML="$WORK_DIR/_temp.html"
      register_temp "$TEMP_HTML"
      ebook-convert "$INPUT" "$TEMP_HTML" 2>/dev/null || true
      if [ -f "$TEMP_HTML" ]; then
        pandoc "$TEMP_HTML" -f html -t markdown --wrap=none -o "$WORK_DIR/$SLUG.md"
      else
        echo "ERRO: Nao foi possivel extrair texto. PDF escaneado precisa de OCR."
        mv "$RAW_TXT" "$WORK_DIR/$SLUG.md"
      fi
    else
      show_progress 2 2 "Formatando texto -> Markdown..."
      sed '/^[[:space:]]*$/{ N; /^\n[[:space:]]*$/d; }' "$RAW_TXT" > "$WORK_DIR/$SLUG.md"
    fi
    ;;

  txt)
    show_progress 1 1 "Convertendo TXT -> Markdown..."
    cp "$INPUT" "$WORK_DIR/$SLUG.md"
    ;;

  html|htm)
    show_progress 1 1 "Convertendo HTML -> Markdown com Pandoc..."
    pandoc "$INPUT" -f html -t markdown --wrap=none -o "$WORK_DIR/$SLUG.md"
    ;;

  *)
    echo "ERRO: Formato '$EXT_LOWER' nao suportado."
    echo "  Formatos aceitos: epub, mobi, azw, azw3, kfx, pdf, txt, html"
    echo "  Sugestao: converta para ePub usando Calibre ou LibreOffice."
    exit "$EXIT_INPUT_ERROR"
    ;;
esac

metrics_step_end "conversao"

# --- Stats + Preview curto (v1.6) ---
if [ -f "$WORK_DIR/$SLUG.md" ]; then
  LINES=$(wc -l < "$WORK_DIR/$SLUG.md" | tr -d ' ')
  WORDS=$(wc -w < "$WORK_DIR/$SLUG.md" | tr -d ' ')
  SIZE=$(filesize "$WORK_DIR/$SLUG.md")
  SIZE_KB=$(echo "scale=1; $SIZE/1024" | bc)

  echo ""
  echo "=== Conversao completa ==="
  echo "Arquivo: $WORK_DIR/$SLUG.md"
  echo "Linhas: $LINES"
  echo "Palavras: $WORDS"
  echo "Tamanho: ${SIZE_KB}KB"
  echo ""
  echo "Preview (10 primeiras linhas):"
  echo "---"
  head -10 "$WORK_DIR/$SLUG.md"
  if [ "$LINES" -gt 10 ]; then
    echo "... ($LINES linhas no total)"
  fi
  echo "---"

  # --- Metadata JSON (v1.8) ---
  ORIGINAL_SIZE=$(filesize "$INPUT")
  PROCESSING_TIME=$(( $(date +%s) - METRICS_START_TIME ))

  write_metadata "$WORK_DIR/metadata.json" \
    "source=$(basename "$INPUT")" \
    "service=ebook-to-md" \
    "format=$EXT_LOWER" \
    "title=${META_TITLE:-desconhecido}" \
    "author=${META_AUTHOR:-desconhecido}" \
    "pages=${META_PAGES:-0}" \
    "word_count=$WORDS" \
    "line_count=$LINES" \
    "processing_time_seconds=$PROCESSING_TIME" \
    "file_size_bytes=$ORIGINAL_SIZE"

  # --- Metrics JSON (v1.9) ---
  CONV_DUR="${STEP_DURATION_conversao:-0}"
  write_metrics "$WORK_DIR/metrics.json" \
    "conversao=$CONV_DUR"

  log_info "Processamento concluido com sucesso"
else
  echo "ERRO: Conversao falhou. Nenhum arquivo de saida gerado."
  echo "  Verifique se o arquivo original nao esta corrompido."
  exit "$EXIT_PROCESSING_ERROR"
fi
