---
name: ig-text
description: |
  Extrai transcrição de vídeos/reels do Instagram. Tenta captions nativas primeiro;
  se não existirem (99% dos casos), baixa áudio via yt-dlp e transcreve com Whisper local.
  Detecta idioma nativo e traduz para português brasileiro via Gemini Flash 2.5.
  Formata com Gemini: traduz, corrige português, adiciona títulos, markdown.
  Gera resumo narrativo denso + plano de ação estruturado. Dashboard com tokens e custo.

  Use: `/ig-text https://www.instagram.com/reel/...`
---

# ig-text — Transcrição Instagram via Captions/Whisper + Gemini

Script embutido nesta skill (`scripts/ig-text.sh`), sem dependência externa.

## Como usar

Receba a URL do Instagram do usuário e execute, a partir da pasta desta skill:

```bash
bash scripts/ig-text.sh "<url>"
```

Para escolher onde salvar a saída, defina `OUTPUT_ROOT` antes de rodar (ex:
`OUTPUT_ROOT=/caminho/de/saida bash scripts/ig-text.sh "<url>"`). Sem isso,
salva em `./outputs/videos/` relativo ao diretório de trabalho atual.

Aceita:
- Reels: `https://www.instagram.com/reel/xxx/`
- Posts com vídeo: `https://www.instagram.com/p/xxx/`

## Como funciona

1. Tenta extrair captions/legendas nativas do Instagram via yt-dlp
2. Se não houver captions (maioria dos casos):
   - Baixa áudio via yt-dlp
   - Converte para 16kHz mono WAV
   - Transcreve com OpenAI Whisper local (modelo base)
3. Gemini traduz para pt-BR (se necessário), formata, corrige, adiciona títulos markdown
4. Gera resumo narrativo denso (10-15% do original)
5. Gera plano de ação estruturado
6. Dashboard visual com progresso, tokens e custo em tempo real
7. Salva em `outputs/videos/{nome-do-video}-{timestamp}/`

## Requisitos
- `yt-dlp` (brew install yt-dlp)
- `ffmpeg` (brew install ffmpeg)
- `jq` (brew install jq)
- `whisper` (pip install openai-whisper) — necessário para Instagram (captions raras)
- `GEMINI_API_KEY` configurada no `.env`

## Diferença do yt-text
- **yt-text**: extrai captions nativas do YouTube (sem baixar vídeo, sem Whisper)
- **ig-text**: tenta captions → fallback Whisper (precisa baixar áudio)
- Pipeline Gemini (tradução, resumo, plano) é idêntico

## Custo médio
- Reel curto (~30s): ~$0.001 + Whisper local (grátis)
- Vídeo longo (~10min): ~$0.01 + Whisper local (grátis)

## Output
```
outputs/videos/{slug}/
├── transcricao.md        ← Transcrição formatada + resumo + plano de ação
├── transcricao-bruta.txt ← Texto bruto (captions ou Whisper)
├── metadata.json         ← Video info + tokens + custo + transcription_method
├── metrics.json          ← Tempos de processamento
└── process.log           ← Log de execução
```
