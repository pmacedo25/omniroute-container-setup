# Sincronização global de skills

Este serviço mantém `project-agents-templates` como fonte central e materializa
skills canônicas no diretório global do Caveman, normalmente
`~/.cave/skills`. Os projetos consumidores não recebem clones nem cópias de
`.agents/`. Não há dependência de OmniRoute, Achilles, MCP ou API própria.

## Fluxo

1. Atualiza o repositório em `/state/source`.
2. Converte `AGENTS.md` e cada `.agents/**/*.md` para o formato canônico
   `SKILL.md`.
3. Materializa cada documento como `/skills/pat-<id>/SKILL.md`.
4. Registra o estado gerenciado em
   `/skills/.project-agents-templates/catalog.json`.

A reconciliação é idempotente. Entradas removidas da fonte são excluídas, mas
somente dentro do namespace `pat-`. Skills criadas pelo usuário no mesmo
diretório nunca são alteradas.

## Contrato para agentes

O Caveman possui descoberta progressiva nativa: lê o frontmatter dos
`~/.cave/skills/*/SKILL.md` para apresentar ao modelo somente nome e descrição,
e lê o corpo da skill escolhida sob demanda. Logo, não é necessário criar uma
ferramenta de roteamento paralela.

A descrição publicada é o primeiro parágrafo útil de cada documento. Escreva-o
como um resumo semântico curto no formato `Use quando: ... Evite quando: ...`,
com termos concretos — tecnologias, arquivos e intenções — que diferenciem essa
skill das demais. Templates e a governança global são publicados com
`disable-model-invocation: true`: continuam disponíveis no catálogo, mas não
concorrem com skills executáveis no mapa inicial do modelo.

Outro agente pode consumir o mesmo diretório usando este contrato:

- enumerar diretórios com um arquivo `SKILL.md`;
- usar apenas `name` e `description` do frontmatter na descoberta;
- abrir o `SKILL.md` completo somente quando a descrição for relevante;
- não carregar todo o catálogo no contexto.

## Configuração

| Variável | Obrigatória | Padrão | Uso |
| --- | --- | --- | --- |
| `SKILLS_REPOSITORY` | sim | - | URL Git da fonte |
| `SKILLS_BRANCH` | não | `main` | Branch da fonte |
| `SKILLS_PATH` | não | autodetectado | Caminho relativo contendo `.github/skills`, skills canônicas ou documentos `.md` |
| `CAVEMAN_SKILLS_DIR` | sim no Compose | - | Caminho global do host montado em `/skills` |
| `SKILLS_SYNC_INTERVAL_SECONDS` | não | `3600` | Intervalo de reconciliação |
| `GITHUB_TOKEN` | para fonte privada | - | Token usado só no header do Git |

O token Git não é escrito em URL, arquivo de credenciais ou catálogo.

## Criar e atualizar

Qualquer novo `.md` em `.agents/` ou `SKILL.md` no padrão
`.github/skills/<nome>/` vira uma skill `pat-*` na sincronização seguinte;
alterações substituem apenas a skill correspondente. Para atualizar
imediatamente, reinicie o serviço:

```powershell
docker compose restart skills-sync
```

O clone privado é um cache interno do sincronizador. Os workspaces de código
continuam sem cópia do repositório de templates.

## Teste local

Em Alpine (ou ambiente com `git` e `jq`):

```sh
sh test.sh
```
