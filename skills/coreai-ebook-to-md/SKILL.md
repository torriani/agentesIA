---
name: ebook-to-md
description: |
  Converte ebooks (ePub, MOBI, AZW, PDF, HTML, TXT) para Markdown formatado.
  100% local, sem LLM, sem custo. Usa Calibre + Pandoc + pdftotext.
  Salva em ./outputs/livros/<nome-do-livro>/ (relativo ao diretório de
  trabalho, ou em OUTPUT_ROOT se definido).

  Use: `/ebook-to-md caminho/do/livro.epub`
---

# Ebook → Markdown

Script embutido nesta skill (`scripts/ebook-to-md.sh`), sem dependência externa.

```bash
bash scripts/ebook-to-md.sh "<arquivo>"
```

Para escolher onde salvar a saída, defina `OUTPUT_ROOT` antes de rodar.
