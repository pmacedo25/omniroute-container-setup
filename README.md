# [Setup Interativo] OmniRoute Gateway + Contas OAuth + IDEs Focadas em IA
# Edição 2026 - Suporte a APPKEY, Combos Padrão, Custom Skills e Roteamento Limpo

Bem-vindo à arquitetura definitiva de roteamento local de LLMs e otimização de tokens. Este projeto foi desenhado para gerenciar o consumo de memória, eliminar janelas pop-up de CMD, sincronizar Skills continuamente de qualquer repositório GitHub e configurar um ambiente de trabalho focado em IA (Roo Code / Cline e Cursor) que consome nativamente os seus Combos Padrão.

---

## [INFO] O Que Há de Novo e Melhorado?

1. **[Arquitetura Limpa e Não-Intrusiva] Preservação das IDEs Oficiais:**
   * Ferramentas oficiais como o **VS Code GitHub Copilot**, **Claude Code App / CLI**, **Codex / ChatGPT Desktop App** e **Antigravity 2.0 / IDE** são mantidas **100% intactas e sem modificações em seus arquivos locais ou variáveis globais do Windows**.
   * Isso garante que os aplicativos nativos continuem funcionando diretamente na nuvem dos seus fabricantes sem erros de UAC, conflitos de HMAC ou travamentos.
2. **[IDEs Focadas em IA] Menu Suspenso Dinâmico com Combos:**
   * Para utilizar todo o poder dos Combos e fallback do OmniRoute, direcionamos o fluxo para ambientes especializados que leem nativamente o endpoint `/v1/models` e exibem os seus Combos diretamente no menu suspenso (dropdown) de modelos do chat:
   * **Roo Code (Antigo Cline) no VS Code:** Extensão autônoma líder de mercado que consome a API "OpenAI Compatible" do Gateway na porta 20128.
   * **Cursor IDE:** Editor autônomo baseado no VS Code que suporta Override Base URL nativamente.
3. **[Setup Interativo de Provedores] Configuração Passo a Passo:**
   * Antes de cadastrar os Combos, o instalador orienta a geração da APPKEY de segurança e faz um loop interativo oferecendo conectar os provedores OAuth (Anthropic, OpenAI, GitHub Copilot) um a um abrindo o painel diretamente no navegador.
4. **[Schema de Modelos Corrigido] Combos Padrão Ativos via API:**
   * O assistente cadastra via REST API os 3 combos padrão usando o schema correto de array de strings (`models: ["provider/model"]`):
     * `combo-coding` (Priority): `anthropic/claude-3-7-sonnet-latest` -> `openai/gpt-4o` -> `github-copilot/claude-3.7-sonnet`
     * `combo-refining` (Priority): `anthropic/claude-3-7-sonnet-latest` -> `openai/o3-mini` -> `github-copilot/gpt-4o`
     * `combo-testing` (Round-Robin): `openai/gpt-4o-mini` -> `anthropic/claude-3-5-haiku-20241022` -> `github-copilot/gpt-4o-mini`
   * Define o `combo-coding` como o roteamento padrão (Default Combo / Global Fallback).
5. **[Sincronização Contínua de Skills] Repositório Customizável:**
   * Você informa a URL do seu repositório Git de prompts e skills no setup (ou usa o padrão `pmacedo25/project-agents-templates`).
   * O sistema clona o repositório em `~/.omniroute/skills` e permite agendar uma tarefa silenciosa no Windows para atualizar as skills a cada 6 horas (`git pull`).
6. **[Zero Pop-ups e Sem Loops] Execução Estável em Background:**
   * Injeção de `NODE_OPTIONS=--max-old-space-size=4096` (evitando erro *out of memory* no SQLite) e execução invisível sem janelas CMD abertas.

---

## [>] Como Executar o Instalador Interativo

Abra o seu terminal **PowerShell** e execute:

```powershell
cd C:\Users\sport\workspace\omniroute-container-setup
.\setup-interativo.ps1
```

### O Fluxo Completo em 5 Etapas:
1. **[ETAPA 1] Escolha do Modo:** Selecione entre Container Isolado (Docker / Podman) ou Nativo Windows (Node.js/NPM).
2. **[ETAPA 2] Repositório de Skills:** Informe a URL do Git de Skills e opte por ativar a sincronização automática no Windows Task Scheduler. O servidor é iniciado silenciosamente na porta 20128.
3. **[ETAPA 3] Autenticação OAuth & APPKEY:** O navegador abre no Dashboard. Você gera e cola sua APPKEY, e o script oferece conectar cada provedor OAuth (Claude, OpenAI, Copilot) interativamente.
4. **[ETAPA 4] Cadastro de Combos Padrão:** O instalador cadastra e atualiza os 3 combos no servidor com os modelos na ordem correta de prioridade.
5. **[ETAPA 5] Configuração de IDEs IA (Roo Code / Cursor):** O script oferece instalar a extensão **Roo Code** no seu VS Code via terminal (`code --install-extension`) e/ou instalar o editor **Cursor IDE** localmente via `winget`, exibindo as instruções limpas de conexão. O comando global `omni` é adicionado ao seu PowerShell.

---

## [INFO] Guia Rápido do Comando 'omni'

Após rodar o setup, você pode controlar e monitorar o Gateway em qualquer terminal PowerShell do Windows:

* `omni status` : Verifica se o servidor está online invisível na porta 20128.
* `omni dash`   : Abre o painel Web de gerenciamento (http://localhost:20128/dashboard).
* `omni logs`   : Acompanha os logs de requisições em tempo real.
* `omni restart`: Reinicia o Gateway em background silencioso sem abrir janelas.
* `omni pull`   : Sincroniza e atualiza imediatamente suas Skills do GitHub (`~/.omniroute/skills`).
* `omni reset-db`: Reseta o banco SQLite caso corrompido e reinicia o serviço limpo.
