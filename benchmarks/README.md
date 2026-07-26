# Benchmark dos combos

O benchmark deve comparar custo por tarefa concluída, não apenas preço por token.
Execute cada caso com uma conversa nova e o mesmo snapshot do repositório.

## Matriz de modelos

| Faixa | Modelo | Provider | Família | Papel |
|---|---|---|---|---|
| Econômica | `gemini-3.1-flash-lite` | Antigravity | Gemini | Principal do `combo-testing` |
| Econômica | `gpt-5.3-codex-spark` | Codex | OpenAI/Codex | Fallback do `combo-testing` |
| Econômica | `gpt-oss-120b-medium` | Antigravity | GPT-OSS | Fallback independente do `combo-testing` |
| Intermediária | `gemini-3.1-pro-low` | Antigravity | Gemini | Principal do `combo-coding` |
| Intermediária | `gpt-5.5-medium` | Codex | OpenAI/Codex | Fallback do `combo-coding` |
| Intermediária | `claude-sonnet-4-6` | Antigravity | Anthropic/Claude | Último fallback do `combo-coding` |
| Alta | `gpt-5.5-high` | Codex | OpenAI/Codex | Principal do `combo-refining` |
| Alta | `claude-sonnet-4-6` | Antigravity | Anthropic/Claude | Fallback do `combo-refining` |
| Alta | `gemini-3.1-pro-high` | Antigravity | Gemini | Terceiro modelo do `combo-refining` |

> Atualmente existem duas conexões ativas no OmniRoute (`codex` e
> `antigravity`). Claude é uma família servida pelo Antigravity, não uma conexão
> Anthropic direta. Ao conectar um terceiro provider, registre-o nesta matriz e
> compare-o sem remover os resultados históricos.

## Casos

1. Explorar um repositório e explicar sua arquitetura.
2. Criar testes para uma função existente.
3. Corrigir um bug com reprodução fornecida.
4. Implementar uma alteração em três arquivos.
5. Refatorar sem alterar comportamento.
6. Investigar uma falha de build.
7. Revisar um diff em busca de regressões e segurança.
8. Executar ferramentas e corrigir o resultado até os testes passarem.
9. Trabalhar em uma conversa longa que acione condensação.
10. Recuperar-se de uma resposta inválida ou indisponibilidade do primeiro modelo.

## Métricas obrigatórias

- sucesso sem intervenção;
- testes aprovados;
- chamadas por tarefa e posição de failover;
- tokens de entrada, cache, saída e reasoning;
- custo total estimado;
- tempo até a primeira resposta e tempo total;
- erros de tool calling;
- arquivos lidos e alterados;
- tamanho do contexto antes e depois de RTK/Caveman;
- nota humana de correção de 1 a 5.

O vencedor é o menor custo médio entre execuções aprovadas. Resultados que não
concluem a tarefa não devem parecer econômicos por terem usado poucos tokens.
