# 🚀 Setup Interativo: OmniRoute Gateway + Contas de IDE + GitHub Skills (`Universal IDEs`)
# Edição 2026 - Suporte a APPKEY, Default Combos Padrão, Custom Skills URL e Zero Popups

Bem-vindo à arquitetura definitiva de roteamento local de LLMs e otimização de tokens (Edição 2026). Este projeto foi salvo no seu Workspace em `C:\Users\sport\workspace\omniroute-container-setup` e foi desenhado para **eliminar loops de janelas CMD**, gerenciar consumo de memória, sincronizar Skills continuamente do GitHub, automatizar seus **Combos Padrão (`Default Combos`)** com uma **APPKEY** unificada e configurar **todas as suas IDEs, Apps Desktop e CLIs automaticamente na raiz**!

---

## 🌟 O Que Há de Novo nesta Versão?

1. **💻 Cobertura Total de IDEs e CLIs (Automação na Raiz):** Seja rodando em Container ou Nativo, o instalador localiza e reescreve as configurações de proxy e chave para 100% das suas ferramentas de desenvolvimento:
   * **Antigravity 2.0 (App Desktop), Antigravity IDE (VS Code-based) e Antigravity CLI (`agy`)**: Configura `GEMINI_BASE_URL` / `GOOGLE_GENAI_BASE_URL` e edita o `settings.json` em `%APPDATA%\Antigravity IDE\User`.
   * **Claude Code App (Windows Desktop) e Claude CLI (`claude`)**: Configura `ANTHROPIC_BASE_URL`, chave e modelo default com notificação de broadcast para o Windows Explorer.
   * **Codex CLI (`codex`) e OpenAI Desktop App**: Cria/atualiza direto no arquivo `%USERPROFILE%\.codex\config.toml`.
   * **VS Code & GitHub Copilot**: Injeta o bloco `github.copilot.advanced` no `%APPDATA%\Code\User\settings.json`.
2. **🌐 Repositório de Skills Customizável e Sincronização Contínua:** No momento do setup, você informa a URL do seu repositório do GitHub (ou usa o padrão `pmacedo25/project-agents-templates`). O instalador clona o repositório Git diretamente em `~/.omniroute/skills`, permitindo atualizações dinâmicas por `omni pull` ou pelo agendador em segundo plano.
3. **⏰ Atualização Automática de Skills:** No Windows Nativo, o assistente oferece criar uma Tarefa Agendada invisível do Windows (Task Scheduler) que faz um `git pull` silencioso a cada 6 horas. No modo Container, um loop interno no Docker faz o mesmo.
4. **🔑 Automação com APPKEY Unificada:** O assistente orienta você a gerar sua APPKEY de segurança no Dashboard e a salva nas variáveis do sistema (`OMNIROUTE_API_KEY`). Todas as suas IDEs já ficam autenticadas automaticamente!
5. **🎯 Cadastro Automático de Default Combos via API:** Com a APPKEY em mãos, o instalador cadastra via REST API os 3 combos padrão do ecossistema (`combo-coding`, `combo-refining`, `combo-testing`) e define o `combo-coding` como o **Fallback Global (Default Combo)**.
6. **🚫 Zero Pop-ups e Sem Loops de CMD:** Injeção de `NODE_OPTIONS=--max-old-space-size=4096` (evitando erro *out of memory* no driver SQLite) e execução silenciosa em background sem a flag `--daemon`.
7. **🧹 Atalho de Recuperação Rápida (`omni reset-db`):** Se em algum teste ou pico de luz o arquivo SQLite for corrompido, basta rodar `omni reset-db` para limpar a trava e reiniciar o serviço limpo em 2 segundos.

---

## 🚀 Como Executar o Instalador Interativo

Abra o seu **PowerShell** e rode o script na pasta do workspace:

```powershell
cd C:\Users\sport\workspace\omniroute-container-setup
.\setup-interativo.ps1
```

### O que o Assistente faz em 5 Etapas:
1. **Escolha do Modo:** Você escolhe se quer rodar em Container (Docker/Podman) ou Nativo Windows.
2. **Configuração de Skills do GitHub:** Você digita a URL do seu repositório de agentes/prompts (ou dá Enter para o padrão) e escolhe se deseja ativar a sincronização automática a cada 6 horas. O servidor liga de forma silenciosa e estável.
3. **Autenticação OAuth e APPKEY:** Abre o Dashboard (`http://localhost:20128/dashboard`). Você loga com suas contas (Claude Pro, ChatGPT, Copilot) na aba *OAuth*, clica em *API Keys* para gerar sua APPKEY, e a cola no terminal.
4. **Automação de Combos Padrão:** O script se conecta via API REST usando a APPKEY e cadastra os combos e regras de fallback para você.
5. **Automação Universal de IDEs & Atalho:** Injeta proxy e chave na raiz do **Antigravity 2.0 / IDE / CLI**, **Claude Code App / CLI**, **Codex CLI / App**, e **VS Code Copilot**, disparando o broadcast do Windows (`WM_SETTINGCHANGE`) e instalando o atalho `omni`.

---

## ⚡ Guia Rápido do Comando `omni`

Após rodar o setup, você pode controlar o Gateway em qualquer terminal PowerShell do Windows:

* `omni status` $\rightarrow$ Verifica se o servidor está online de forma silenciosa e instantânea.
* `omni dash` $\rightarrow$ Abre o painel visual no seu navegador.
* `omni logs` $\rightarrow$ Exibe os logs em tempo real sem travar a tela.
* `omni restart` $\rightarrow$ Reinicia o serviço em background silencioso (com aumento de memória e zero janelas abertas).
* `omni pull` $\rightarrow$ Força a atualização imediata (`git pull`) das suas Skills no repositório `~/.omniroute/skills`.
* `omni reset-db` $\rightarrow$ Destrava e limpa o banco SQLite caso corrompa, reiniciando o serviço limpo.
* `omni model <combo>` $\rightarrow$ Altera o combo padrão do Claude Code em tempo real (ex: `omni model combo-refining`).

---

## 💻 Resumo das Configurações Injetadas pelo Setup

### 1. Antigravity IDE (`%APPDATA%\Antigravity IDE\User\settings.json`) e VS Code Copilot (`%APPDATA%\Code\User\settings.json`):
```json
{
  "github.copilot.advanced": {
    "debug.overrideProxyUrl": "http://localhost:20128/v1",
    "debug.overrideApiKey": "sk-omni-sua-appkey-aqui"
  }
}
```

### 2. Codex CLI (`%USERPROFILE%\.codex\config.toml`):
```toml
[model_providers.openai]
name = "openai"
base_url = "http://localhost:20128/v1"
api_key = "sk-omni-sua-appkey-aqui"
```

### 3. Antigravity 2.0 / CLI (`agy`) e Claude Code App / CLI (Variáveis + Broadcast):
```powershell
GEMINI_BASE_URL="http://localhost:20128/v1"
GOOGLE_GENAI_BASE_URL="http://localhost:20128/v1"
ANTHROPIC_BASE_URL="http://localhost:20128/v1"
OPENAI_BASE_URL="http://localhost:20128/v1"
OMNIROUTE_API_KEY="sk-omni-sua-appkey-aqui"
```

Tudo pronto para programar com economia de tokens, gestão de contexto, atualização contínua de skills e failover automático em todo o seu ecossistema IA!
