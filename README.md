# [Setup Interativo] OmniRoute Gateway + Contas OAuth + IDEs Desktop (OpenCode & OpenHands)
# Edição 2026 - Suporte a APPKEY, Combos Padrão, Custom Skills e Arquitetura 100% BYOK (Sem Login)

Bem-vindo à arquitetura definitiva de roteamento local de LLMs e otimização de tokens. Este projeto foi desenhado para gerenciar o consumo de memória, eliminar janelas pop-up de CMD, sincronizar Skills continuamente de qualquer repositório GitHub e integrar perfeitamente com IDEs Desktop abertas e sem login obrigatório (OpenCode Desktop e OpenHands Desktop) consumindo nativamente os seus Combos Padrão.

---

## [INFO] O Que Há de Novo e Melhorado?

1. **[Arquitetura 100% BYOK & Sem Login Obrigatório] IDEs Desktop Autônomas:**
   * **OpenCode Desktop:** IDE/Agente nativo 100% open-source que aceita a URL Base `http://localhost:20128/v1` e sua APPKEY sem exigir criação de conta ou logins proprietários.
   * **OpenHands Desktop:** Plataforma desktop de agentes de desenvolvimento autônomos com suporte nativo a LLMs customizados via OpenAI Compatible API.
   * **Remoção do Cursor e Extensões:** Eliminamos totalmente a dependência do Cursor (que exige login proprietário) e extensões do VS Code.
2. **[Preservação das IDEs Oficiais] Funcionamento Nativo Intacto:**
   * As IDEs e ferramentas oficiais (**VS Code Copilot**, **Claude Code App**, **Codex / ChatGPT App**, **Antigravity**) permanecem **100% intactas e puras**, permitindo que você as use nativamente na nuvem dos fabricantes quando desejar.
3. **[Detecção Inteligente de Reinstalação & Criptografia Blindada]:**
   * **Reinstalação Preservada:** Se o OmniRoute já estiver instalado, o assistente detecta e permite manter seus bancos de dados SQLite e reutilizar a APPKEY existente em 2 segundos sem perder contas logadas.
   * **Fix de Criptografia (`STORAGE_ENCRYPTION_KEY`):** Garante que o arquivo `.env` (tanto no Windows quanto no Contêiner Docker/Podman) contenha a chave de criptografia do banco antes de iniciar o servidor, eliminando o erro *Internal Server Error* na criação de API Keys.
4. **[Schema de Modelos Corrigido] Combos Padrão Ativos via API:**
   * O assistente cadastra via REST API os 3 combos padrão usando o schema correto de array de strings (`models: ["provider/model"]`):
     * `combo-coding` (Priority): `anthropic/claude-3-7-sonnet-latest` -> `openai/gpt-4o` -> `github-copilot/claude-3.7-sonnet`
     * `combo-refining` (Priority): `anthropic/claude-3-7-sonnet-latest` -> `openai/o3-mini` -> `github-copilot/gpt-4o`
     * `combo-testing` (Round-Robin): `openai/gpt-4o-mini` -> `anthropic/claude-3-5-haiku-20241022` -> `github-copilot/gpt-4o-mini`
   * Define o `combo-coding` como o roteamento padrão (Default Combo / Global Fallback).
5. **[Sincronização Contínua de Skills] Repositório Customizável:**
   * Você informa a URL do seu repositório Git de prompts e skills no setup (ou usa o padrão `pmacedo25/project-agents-templates`).
   * No modo Contêiner, o servidor atualiza as skills automaticamente a cada 1 hora (`git pull`). No modo Nativo Windows, atualize quando quiser via `omni pull`.

---

## [>] Como Executar o Instalador Interativo

Abra o seu terminal **PowerShell** e execute:

```powershell
cd C:\Users\sport\workspace\omniroute-container-setup
.\setup-interativo.ps1
```

### O Fluxo Completo em 5 Etapas:
1. **[ETAPA 1] Escolha do Modo:** Selecione entre Container Isolado (Docker / Podman) ou Nativo Windows (Node.js/NPM).
2. **[ETAPA 2] Repositório de Skills:** Informe a URL do Git de Skills. O servidor é iniciado silenciosamente na porta 20128 com criptografia validada.
3. **[ETAPA 3] Autenticação OAuth & APPKEY:** O navegador abre no Dashboard para conectar seus provedores (Claude, OpenAI, Copilot). Se for reinstalação, você pode reutilizar a APPKEY existente.
4. **[ETAPA 4] Cadastro de Combos Padrão:** O instalador cadastra e atualiza os 3 combos no servidor com os modelos na ordem correta de prioridade.
5. **[ETAPA 5] Configuração de IDEs Desktop (OpenCode / OpenHands):** Exibe as instruções de conexão limpas sem necessidade de logins proprietários. O comando global `omni` é ativado no PowerShell.

---

## [INFO] Guia Rápido do Comando 'omni'

Após rodar o setup, você pode controlar e monitorar o Gateway em qualquer terminal PowerShell do Windows (com suporte híbrido a Container e Nativo):

* `omni status` : Verifica se o servidor está online na porta 20128.
* `omni dash`   : Abre o painel Web de gerenciamento (http://localhost:20128/dashboard).
* `omni logs`   : Acompanha os logs de requisições em tempo real (Tail local ou `docker logs -f`).
* `omni restart`: Reinicia o Gateway em background silencioso (ou `docker compose restart`).
* `omni pull`   : Sincroniza e atualiza imediatamente suas Skills do GitHub (`~/.omniroute/skills` e container).
* `omni reset-db`: Reseta o banco SQLite caso corrompido e reinicia o serviço limpo.
