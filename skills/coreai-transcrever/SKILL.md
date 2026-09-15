---
name: transcrever
description: |
  Transcreve vídeos e áudios usando OpenAI Whisper local (sem API paga).
  Otimiza o áudio para mono 16kHz + 2x speed, reduzindo tempo e memória pela metade.
  Suporta português e inglês. Salva em ./outputs/transcriptions/ (relativo ao
  diretório de trabalho, ou em OUTPUT_ROOT se definido).

  Use: `/transcrever caminho/do/video.mp4` ou `/transcrever caminho/do/audio.mp3 en large 1`
---

# Transcrever Vídeo/Áudio

Script embutido nesta skill (`scripts/transcrever.sh`), sem dependência externa.

```bash
bash scripts/transcrever.sh "<arquivo>" "<idioma>" "<modelo>" "<velocidade>"
```

Defaults: idioma=pt, modelo=medium, velocidade=2. Para escolher onde salvar a
saída, defina `OUTPUT_ROOT` antes de rodar.
