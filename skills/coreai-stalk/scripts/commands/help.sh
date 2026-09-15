#!/usr/bin/env bash
# stalk/scripts/commands/help.sh

set -euo pipefail

CMD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILL_DIR="$(cd "$CMD_DIR/../.." && pwd)"
source "$SKILL_DIR/scripts/lib/env.sh"
source "$SKILL_DIR/scripts/lib/apify.sh"

stalk_cmd_help() {
  cat <<'EOF'

╔════════════════════════════════════════════════════════════╗
║  /stalk — Inteligência Competitiva Instagram               ║
╚════════════════════════════════════════════════════════════╝

🎯 CONSOLIDADOS (uso principal)

  /stalk profile @handle [flags]
    --reels                  Foco em Reels com hooks transcritos
    --top --period 30d       Top posts de N dias
    --stories                Stories ativos + highlights
    --snapshot               Salva estado para diff futuro
    --me                     Usa handle padrão (config)
    --client <slug>          Pasta de output específica

  /stalk search "termo" [flags]   (detecta # automaticamente)
    --hooks                  Só os hooks dos top 50
    --angles                 Agrupa por ângulo narrativo
    --swipe                  Banco de hooks/CTAs/estruturas
    --find-perfis            Retorna perfis em vez de posts
    --lang pt|en|es          Filtro de idioma
    --top N                  Quantidade (padrão 30)
    --period 30d|60d|90d     Janela temporal

  /stalk dossie @handle [flags]
    (sem flag)               Relatório imperial completo
    --vs @x @y               Comparativo lado a lado

  /stalk comments <url>      Vocabulário do avatar
  /stalk help                Esta tela
  /stalk config              Configurar handle/idioma/cliente

🔧 ATALHOS INDIVIDUAIS

  /stalk keyword "X"         → search "X"
  /stalk hashtag #tag        → search "#tag"
  /stalk hooks "X"           → search "X" --hooks
  /stalk angles "X"          → search "X" --angles
  /stalk swipe "X"           → search "X" --swipe
  /stalk competitors "nicho" → search "nicho" --find-perfis
  /stalk reels @x            → profile @x --reels
  /stalk top @x              → profile @x --top
  /stalk stories @x          → profile @x --stories
  /stalk track @x            → profile @x --snapshot
  /stalk mine                → profile --me
  /stalk compare @a @b @c    → dossie @a --vs @b @c

EOF

  echo "🔐 STATUS DO TOKEN"
  if stalk_load_env 2>/dev/null && [[ -n "${APIFY_TOKEN:-}" ]]; then
    local username
    username=$(stalk_get_username 2>/dev/null || echo "?")
    echo "  ✅ Configurado (conta: $username)"
    local credits
    credits=$(apify_credits 2>/dev/null || echo "?")
    echo "  💰 Limite mensal de créditos: \$${credits} USD"
  else
    echo "  ❌ Token não configurado. Use qualquer comando para fazer bootstrap."
  fi
  echo ""

  echo "💵 CUSTO ESTIMADO POR OPERAÇÃO (Apify STARTER)"
  echo "  profile/dossie:   ~\$0.01 USD"
  echo "  search keyword:   ~\$0.05–0.10 USD"
  echo "  search hashtag:   ~\$0.03–0.05 USD"
  echo "  comments:         ~\$0.02 USD"
  echo "  reels:            ~\$0.02 USD"
  echo ""
  echo "📂 Output: \${STALK_OUTPUT_BASE:-./outputs/copys}/{cliente}/inteligencia/"
  echo "📚 Docs:   $SKILL_DIR/README.md"
  echo ""
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  stalk_cmd_help "$@"
fi
