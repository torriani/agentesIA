# stalk — Inteligência Competitiva Instagram

Skill global para Claude Code. Espreita perfis, busca por palavra-chave, gera dossiê completo, extrai vocabulário do avatar via comentários.

Tom NÚCLEO Torriani: você não pesquisa, você espreita.

## Instalação

A skill está em `~/.claude/skills/stalk/`. Para instalar do zero em outra máquina:

```bash
# 1. Copiar a pasta
cp -r stalk ~/.claude/skills/

# 2. Garantir permissões de execução
chmod +x ~/.claude/skills/stalk/scripts/stalk.sh \
  ~/.claude/skills/stalk/scripts/bootstrap.sh \
  ~/.claude/skills/stalk/scripts/lib/*.sh \
  ~/.claude/skills/stalk/scripts/commands/*.sh
```

Pronto. Próxima vez que você invocar `/stalk` no Claude Code, a skill é descoberta automaticamente pelo SKILL.md.

## Primeira execução (bootstrap)

Quando você roda qualquer comando pela primeira vez, a skill detecta que não tem token Apify e dispara o bootstrap:

```
⚠️  Token Apify não encontrado.

📝 PASSO A PASSO (3 minutos):
  1. Acesse: https://console.apify.com/sign-up
  2. Crie conta (Google login OK)
  3. Vá em: https://console.apify.com/account/integrations
  4. Copie o "Personal API token" (começa com apify_api_...)

Cole o token aqui: _
```

Cole o token, ele é validado via `GET /users/me` e salvo em `~/.claude/.env.global` com permissão 600. A partir daí, transparente.

## Lookup de credenciais

A skill busca o token em 3 camadas, na ordem:

1. **`$APIFY_TOKEN` no shell** (override temporário — `export APIFY_TOKEN=...`)
2. **`~/.claude/.env.global`** (padrão pra usuário recorrente)
3. **Bootstrap interativo** (primeira vez ou token inválido)

## Uso — 18 comandos

### Consolidados (cobrem 90% do uso)

```bash
# Análise de perfil (e variações via flag)
/stalk profile @raulbergesch
/stalk profile @raul --reels
/stalk profile @raul --top --period 30d
/stalk profile @raul --stories
/stalk profile @raul --snapshot          # arquiva pra diff futuro
/stalk profile --me                      # usa handle padrão (config)

# Pesquisa por termo (detecta # automaticamente)
/stalk search "advogado pme"
/stalk search "#planejamentosucessorio"
/stalk search "advogado pme" --hooks --top 50 --lang pt
/stalk search "sucessao" --angles
/stalk search "tributacao" --swipe
/stalk search "nicho" --find-perfis

# Dossiê imperial (relatório denso estilo Bergesh)
/stalk dossie @raulbergesch
/stalk dossie @raul --vs @x @y           # comparativo
/stalk dossie @raul --client bergesh-advogados

# Comentários → vocabulário do avatar
/stalk comments https://www.instagram.com/p/XXX/

# Utilitários
/stalk help                              # comandos + status token + créditos
/stalk config                            # ver config atual
/stalk config default_handle juliano.torriani
/stalk config default_client bergesh-advogados
```

### Atalhos individuais (uso pontual)

```bash
/stalk keyword "termo"      # = search "termo"
/stalk hashtag tag          # = search "#tag"
/stalk hooks "termo"        # = search "termo" --hooks
/stalk angles "termo"       # = search "termo" --angles
/stalk swipe "termo"        # = search "termo" --swipe
/stalk competitors "nicho"  # = search "nicho" --find-perfis

/stalk reels @x             # = profile @x --reels
/stalk top @x               # = profile @x --top
/stalk stories @x           # = profile @x --stories
/stalk track @x             # = profile @x --snapshot
/stalk mine                 # = profile --me

/stalk compare @a @b @c     # = dossie @a --vs @b @c
```

## Output

Todos os comandos salvam em estrutura previsível:

```
${STALK_OUTPUT_BASE:-./outputs/copys}/{cliente}/inteligencia/{tipo}/{slug}/
├── data.json       # dados crus Apify
├── analysis.md     # intermediário (opcional)
└── RELATORIO.md    # entrega final ao usuário
```

Cliente padrão: `default`. Configure com `/stalk config default_client <slug>` ou flag `--client <slug>`.

## Custo

Plano Apify STARTER ($29/mês):

| Operação | Custo médio |
|----------|-------------|
| profile / mine / dossie (1 perfil) | ~$0.01 |
| search keyword | ~$0.05–0.10 |
| search hashtag | ~$0.03–0.05 |
| comments | ~$0.02 |
| reels | ~$0.02 |
| compare (3 perfis) | ~$0.03 |

Para ver créditos restantes: `/stalk help`.

## Pipeline interno

```
1. router (stalk.sh) parseia comando + flags
2. env.sh garante APIFY_TOKEN (chama bootstrap se faltar)
3. apify.sh executa scrape via REST API → data.json
4. Claude lê data.json + prompt em prompts/ → análise
5. output.sh salva em pasta padrão + imprime relatório
```

A análise é feita pelo próprio Claude lendo prompts pré-construídos:
- `prompts/analyze-profile.md`
- `prompts/analyze-search.md`
- `prompts/analyze-dossie.md`
- `prompts/analyze-comments.md`

Os prompts seguem padrão do `@competitor-analyst` do squad Conteudo.

## Segurança

- Token salvo com `chmod 600` (só seu user lê)
- Skill nunca loga o token
- Se `~/.claude/` for git repo, `.env.global` é adicionado ao `.gitignore` automaticamente
- Bootstrap valida token via `/users/me` antes de salvar

## Troubleshooting

**Token inválido:** Rode `/stalk` qualquer comando — bootstrap dispara automaticamente.

**Perfil retorna vazio:** Provavelmente é privado ou não existe. Confere o handle.

**Rate limit (429):** A skill já faz retry exponencial (5/15/45s). Se persistir, aguarda alguns minutos.

**Quero usar outra conta Apify:** `rm ~/.claude/.env.global` e roda qualquer comando — bootstrap roda de novo.

## Estrutura de arquivos

```
~/.claude/skills/stalk/
├── SKILL.md                  # entrypoint Claude Code
├── README.md                 # este arquivo
├── config.yaml               # criado pelo /stalk config
├── scripts/
│   ├── stalk.sh              # router principal
│   ├── bootstrap.sh          # primeira execução
│   ├── lib/
│   │   ├── env.sh            # lookup do token (3 camadas)
│   │   ├── apify.sh          # wrapper REST com retry
│   │   └── output.sh         # paths padronizados
│   └── commands/
│       ├── profile.sh        # /stalk profile (consolidado)
│       ├── search.sh         # /stalk search (consolidado)
│       ├── dossie.sh         # /stalk dossie (consolidado)
│       ├── comments.sh       # /stalk comments
│       ├── help.sh           # /stalk help
│       └── config.sh         # /stalk config
├── prompts/
│   ├── analyze-profile.md
│   ├── analyze-search.md
│   ├── analyze-dossie.md
│   └── analyze-comments.md
└── data/
    └── apify-actors.yaml     # catálogo de actors usados
```

## Roadmap

- v1.0 (atual): Instagram, REST API
- v1.1: TikTok (`--platform tiktok`)
- v1.2: Meta Ads Library
- v1.3: YouTube Shorts
- v2.0: Integração via Docker MCP (acessível pelos squads sem rodar via skill)
