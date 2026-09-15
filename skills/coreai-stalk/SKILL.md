---
name: stalk
description: Inteligência competitiva para Instagram. Espreita perfis, busca por palavra-chave/hashtag, gera dossiê de inteligência completo, extrai vocabulário do avatar via comentários. 18 comandos (6 consolidados + 12 atalhos). Use quando o usuário pedir análise de concorrente, pesquisa de termo/hashtag no Instagram, dossiê de perfil, banco de hooks/swipe, espionagem de conteúdo, ou inteligência de mercado em redes sociais.
---

# stalk — Inteligência Competitiva Instagram

Skill global de espionagem e análise estratégica de Instagram. Tom NÚCLEO Torriani: você não pesquisa, você espreita.

## Contexto do cliente (ContextOS)

Antes de produzir dossiê ou banco de swipe: leia `../coreai-shared/contextos-contract.md`,
resolva o negócio ativo e só prossiga com READY. Sem contexto validado, bloqueie a produção
e ofereça `coreai-contexto`.

## Quando usar

Invoque esta skill quando o usuário:
- Pedir análise de perfil (próprio ou concorrente)
- Pedir pesquisa por palavra-chave ou hashtag
- Pedir dossiê de inteligência sobre alguém
- Quiser banco de hooks, CTAs ou estruturas que estão funcionando
- Pedir comparativo entre perfis
- Quiser extrair vocabulário do avatar (via comentários)
- Mencionar termos: "espia", "stalk", "analisa esse perfil", "o que tá bombando sobre", "concorrentes de", "raio-x do perfil"

## Comandos disponíveis (18)

### Consolidados (uso principal)

| Comando | Função |
|---------|--------|
| `/stalk profile @handle [flags]` | Análise de perfil. Flags: `--reels`, `--top`, `--stories`, `--snapshot`, `--me` |
| `/stalk search "termo" [flags]` | Pesquisa por keyword/hashtag. Flags: `--hooks`, `--angles`, `--swipe`, `--find-perfis`, `--lang`, `--top`, `--period` |
| `/stalk dossie @handle [flags]` | Relatório imperial completo. Flags: `--vs @x @y`, `--client <slug>` |
| `/stalk comments <url>` | Vocabulário do avatar via comentários |
| `/stalk help` | Lista comandos + status token + créditos |
| `/stalk config` | Configurar handle padrão, idioma, cliente |

### Atalhos individuais (uso pontual)

| Atalho | Equivale a |
|--------|------------|
| `/stalk keyword "X"` | `/stalk search "X"` |
| `/stalk hashtag #tag` | `/stalk search "#tag"` |
| `/stalk hooks "X"` | `/stalk search "X" --hooks` |
| `/stalk angles "X"` | `/stalk search "X" --angles` |
| `/stalk swipe "X"` | `/stalk search "X" --swipe` |
| `/stalk competitors "X"` | `/stalk search "X" --find-perfis` |
| `/stalk reels @x` | `/stalk profile @x --reels` |
| `/stalk top @x` | `/stalk profile @x --top` |
| `/stalk stories @x` | `/stalk profile @x --stories` |
| `/stalk track @x` | `/stalk profile @x --snapshot` |
| `/stalk mine` | `/stalk profile --me` |
| `/stalk compare @a @b @c` | `/stalk dossie @a --vs @b @c` |

## Como executar

A skill é implementada em bash com pipeline:

```
1. Parse comando + flags
2. Carregar APIFY_TOKEN (env shell > ~/.claude/.env.global > bootstrap)
3. Chamar Apify REST API
4. Salvar dados crus + análise em `${STALK_OUTPUT_BASE:-./outputs/copys}/{cliente}/inteligencia/`
5. Imprimir relatório para o usuário
```

**Para executar:** rode `bash scripts/stalk.sh <comando> [args]` (relativo a esta
skill) via Bash tool. Para escolher onde salvar a saída, defina
`STALK_OUTPUT_BASE` antes de rodar.

Exemplo:
```bash
bash scripts/stalk.sh profile @raulbergesch
bash scripts/stalk.sh search "advogado pme" --hooks --top 50
bash scripts/stalk.sh dossie @raulbergesch --client bergesh-advogados
```

## Bootstrap (primeira execução)

Se `APIFY_TOKEN` não existir, a skill executa fluxo interativo:
1. Mostra passo-a-passo pra obter token em https://console.apify.com/account/integrations
2. Pede pro usuário colar o token
3. Valida via `GET /users/me`
4. Salva em `~/.claude/.env.global` (chmod 600)
5. Continua o comando original

## Pipeline de análise

Após scrape, o comando salva `data.json` e invoca análise via prompts em `prompts/`:

- `prompts/analyze-profile.md` — análise de perfil (estilo @competitor-analyst)
- `prompts/analyze-search.md` — análise de busca por termo
- `prompts/analyze-dossie.md` — relatório imperial completo (perfil + gaps + 10 sugestões)
- `prompts/analyze-comments.md` — extração de vocabulário do avatar

A LLM lê `data.json` + prompt e gera `RELATORIO.md` final no output folder.

## Output padrão

```
${STALK_OUTPUT_BASE:-./outputs/copys}/{cliente}/inteligencia/{tipo}/{slug}/
├── data.json       # dados crus Apify
├── analysis.md     # análise estruturada (intermediário)
└── RELATORIO.md    # entrega final ao usuário
```

Cliente padrão: `default`. Override com `--client <slug>` ou `/stalk config`.

## Princípios

- **Análise > dados crus.** Nunca entregar JSON; sempre interpretar com tom imperial.
- **Tom NÚCLEO Torriani.** Provocativo, prescritivo, decreta antes de explicar.
- **Bootstrap on first run.** Funciona out-of-the-box quando outro usuário recebe a skill.
- **Output sempre estruturado.** Pasta padrão, formato padrão.
- **Atalhos são wrappers finos.** Não duplicam código, delegam aos consolidados.
