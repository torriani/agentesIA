---
name: yt-text
description: |
  Extrai transcrição nativa do YouTube (captions/legendas) sem baixar o vídeo.
  Formata com Gemini Flash 2.5: corrige português, adiciona títulos, markdown.
  Gera resumo narrativo denso + plano de ação estruturado. Dashboard com tokens e custo.
  Suporta batch (múltiplos vídeos em sequência).

  Use: `/yt-text https://www.youtube.com/watch?v=...` ou `/yt-text URL en`
---

# yt-text — Transcrição YouTube via Captions + Gemini

Scripts embutidos nesta skill (`scripts/`), sem dependência externa.

## Como usar

### Video único
Receba a URL do YouTube do usuário e execute, a partir da pasta desta skill:

```bash
bash scripts/yt-text.sh "<url>" "<idioma>"
```

### Batch (múltiplos vídeos)
Para processar vários vídeos em sequência:

```bash
# Por argumentos
bash scripts/yt-text-batch.sh "url1" "url2" "url3" --lang pt

# Por arquivo (uma URL por linha)
bash scripts/yt-text-batch.sh --file lista.txt --lang pt
```

Defaults: idioma=pt. Para escolher onde salvar a saída, defina `OUTPUT_ROOT`
antes de rodar (ex: `OUTPUT_ROOT=/caminho/de/saida bash scripts/yt-text.sh ...`).
Sem isso, salva em `./outputs/videos/` relativo ao diretório de trabalho atual.

## Requisitos
- `yt-dlp` (brew install yt-dlp)
- `jq` (brew install jq)
- `GEMINI_API_KEY` configurada no `.env` (carregada automaticamente)

## O que faz
1. Extrai captions/legendas nativas do YouTube (sem baixar vídeo)
2. Para vídeos longos (>6000 palavras): divide em chunks e processa em partes
3. Gemini formata: corrige português, indenta, adiciona títulos markdown
4. Gera resumo narrativo denso (10-15% do original, com seções temáticas e citações)
5. Gera plano de ação estruturado (imediatas / curto prazo / médio prazo + tabela de recursos)
6. Adiciona embed do vídeo `<!-- VIDEO: url -->` para o portal
7. Dashboard visual com progresso, tokens e custo em tempo real
8. Salva em `${OUTPUT_ROOT:-./outputs/videos}/{nome-do-video}-{timestamp}/`

## Custo médio
- Vídeo curto (~10min): ~$0.001
- Vídeo longo (~2h): ~$0.04

## Output
```
{OUTPUT_ROOT}/{slug}/
├── transcricao.md        ← Transcrição formatada + resumo denso + plano de ação
├── transcricao-bruta.txt ← Texto bruto das legendas
├── metadata.json         ← Metadados do vídeo + tokens + custo
├── metrics.json          ← Tempos de processamento
└── process.log           ← Log de execução
```
