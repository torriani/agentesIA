# agentesIA — estado técnico

Última atualização deste documento: 2026-09-14 (após auditoria completa do catálogo).

## Catálogo atual

101 skills instaláveis (`coreai-*`, verificado com
`python3 skills/coreai-setup/scripts/install.py --source skills --list`).
Nenhuma referencia `~/coreaios`, `coreai-mentoria` nem outro path que só exista
na máquina do autor — as poucas encontradas na varredura de 14/09/2026 foram
corrigidas (path relativo dentro da própria skill) ou removidas do catálogo.

73 dessas 101 exigem contexto de negócio válido antes de produzir (leem
`coreai-shared/contextos-contract.md` e bloqueiam sem READY). As 28 restantes
são, por desenho, guarda-chuvas que só delegam, ferramentas de criar/gerir o
próprio ContextOS, meta-ferramentas de skill, utilitários técnicos sem ligação
a marca de cliente, ou a voz autoral fixa do Imperador — não faz sentido elas
pedirem "qual negócio é este".

Este documento não lista as 101 por nome — o catálogo real, sempre atual, é o
resultado do comando `--list` acima. Uma lista fixa aqui ficaria desatualizada
a cada skill nova.

## Removidas do catálogo do aluno (existiam, foram tiradas)

Cada uma tinha um motivo específico, não é lixo aleatório:

- `coreai-ativa-squad`, `coreai-squad-to-skill`: assumem o conceito de "squad
  AIOX", que este pacote não tem. Ferramentas de bastidor do autor.
- `coreai-context-deep`, `coreai-context-enrich`, `coreai-context-quick`:
  duplicavam `coreai-contexto`, que já cobre os mesmos três modos
  (`--mode quick`/`--mode deep`/enrich) com raiz de contexto explícita.
- `coreai-skill-installer`: obsoleta — nenhuma skill do catálogo atual tem
  `install.sh` para ela rodar.
- `coreai-update-gateway`: sincroniza um "Message Gateway" entre dois repos
  que só existem na máquina do autor (`aiox-imersao`, `legacy`). Não é
  corrigível com troca de path.

## Bloqueio de contexto

Skills de produção exigem `--context-root`, `--business` e saída explícita
dentro de `businesses/<cliente>/outputs/`. Sem contexto válido, não gravam.
`contexto.md` é obrigatório; `--require` é aditivo. O gate
(`coreai-shared/scripts/gate.py`) verifica estrutura e fontes, não a
veracidade do conteúdo. Leia cada `SKILL.md` para a interface exata.

## Dependências

Python 3.9+, Node.js. Para PNG (carrossel), na raiz deste pacote:

```sh
npm --prefix skills/coreai-carousel-creator ci
npm --prefix skills/coreai-carousel-creator exec -- playwright install chromium
```

Algumas skills utilitárias têm dependência externa própria (documentada no
`SKILL.md` de cada uma): `yt-dlp`/`jq`/`whisper` para `coreai-yt-text` e
`coreai-ig-text`, `ffmpeg`/`whisper` para `coreai-transcrever`,
Calibre/Pandoc/`pdftotext` para `coreai-ebook-to-md`.

## Saída de arquivos das skills utilitárias

`coreai-yt-text`, `coreai-ig-text`, `coreai-transcrever`, `coreai-ebook-to-md`
e `coreai-stalk` salvam por padrão em uma subpasta `./outputs/...` relativa ao
diretório de trabalho atual. Para escolher outro lugar, defina a variável de
ambiente documentada no `SKILL.md` de cada uma (`OUTPUT_ROOT` na maioria,
`STALK_OUTPUT_BASE` em `coreai-stalk`) antes de rodar.

## Instalação

A instalação sempre grava uma cópia própria de cada skill em
`~/.claude/skills/` e/ou `~/.agents/skills/` — nunca cria link simbólico
apontando de volta para este pacote. Atualizar o pacote (`git pull`) nunca
muda uma skill já instalada até rodar o instalador de novo
(`skills/coreai-setup/scripts/install.py`).

## Ensaios nos aplicativos

Instagram (publicação) foi corrigido e testado com mocks, sem publicação real.
As demais rotas de produção precisam de teste de comportamento real nos
aplicativos (Claude Desktop, Claude Code, Codex) antes de considerar a
cobertura completa — presença do arquivo `SKILL.md` correto não prova que o
fluxo funciona ponta a ponta.

Nenhuma aula, slide, credencial ou dado de cliente acompanha este pacote.

## Setup guiado

Abra [o guia completo](docs/GUIA-SETUP.html): computador, instalação,
ContextOS, Drive, Gemini e Meta. A skill `coreai-setup` conduz as mesmas
etapas. Testes locais não equivalem a conexões externas verificadas.
