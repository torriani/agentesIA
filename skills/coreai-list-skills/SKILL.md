---
name: list-skills
description: |
  Lista todas as skills instaladas no sistema com nome e descricao.
  Escaneia ~/.claude/skills/ e exibe um catalogo formatado.
---

# List Skills

Lista todas as skills disponíveis no sistema.

## Quick Start

```
/list-skills
```

## WORKFLOW

1. **Escanear** todos os diretórios em `~/.claude/skills/`
2. **Ler** o frontmatter YAML de cada `SKILL.md` encontrado (campos `name` e `description`)
3. **Exibir** uma tabela formatada com:

### Formato de saída

```
## Skills Instaladas ({total})

| #  | Skill | Descrição |
|----|-------|-----------|
| 1  | nome  | descricao |
| 2  | nome  | descricao |
...

Diretório: ~/.claude/skills/
```

- Ordenar alfabeticamente pelo nome
- Descrição: usar apenas a primeira linha do campo `description`
- Se um diretório não tiver SKILL.md válido, ignorar silenciosamente

## REGRAS

- NUNCA modificar nenhum arquivo, apenas leitura
- Sempre usar Glob + Read para encontrar e ler os SKILL.md
- Mostrar o total de skills encontradas
