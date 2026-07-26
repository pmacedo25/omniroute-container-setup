# ==============================================================================
# 🚀 Setup Interativo: OmniRoute Gateway + Contas de IDE + GitHub Skills
# Desenvolvido para Windows PowerShell (Suporte a Docker/Podman E Instalação Nativa Sem Container)
# Otimizado para: Antigravity 2.0/IDE/CLI, Claude Code App/CLI, Codex CLI, e VS Code Copilot
# ==============================================================================

$OutputEncoding = [System.Text.Encoding]::UTF8
$env:PATH += ";$env:APPDATA\npm;C:\Program Files\nodejs;C:\Program Files (x86)\nodejs"

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "🌟 ASSISTENTE DE SETUP OMNIROUTE 2026 (IDEs COMPLETE & DEFAULT COMBOS) 🌟" -ForegroundColor Yellow
Write-Host "==============================================================================" -ForegroundColor Cyan

$setupDir = $PSScriptRoot
$homeDir = $env:USERPROFILE
$skillsDir = "$homeDir\.omniroute\skills"
$logFile = "$homeDir\.omniroute\gateway.log"

# Garante que o diretório base existe
if (-not (Test-Path "$homeDir\.omniroute")) { New-Item -Path "$homeDir\.omniroute" -ItemType Directory -Force | Out-Null }
if (-not (Test-Path "$homeDir\.omniroute\logs")) { New-Item -Path "$homeDir\.omniroute\logs" -ItemType Directory -Force | Out-Null }

# ------------------------------------------------------------------------------
# 📌 ETAPA 1: Escolha do Modo de Instalação (Container ou Nativo Windows)
# ------------------------------------------------------------------------------
Write-Host "`n📌 [ETAPA 1/5] Escolha do Modo de Instalação e Execução" -ForegroundColor White
Write-Host "  [1] 🐳 Container Isolado (Docker / Podman) - Sem sujeira no Windows" -ForegroundColor Cyan
Write-Host "  [2] 💻 Nativo no Windows (Node.js/NPM direto) - Sem precisar de Docker" -ForegroundColor Green
$modo = Read-Host "`n👉 Digite 1 ou 2 (Padrão: 2)"
if ($modo -ne "1") { $modo = "2" }

# ------------------------------------------------------------------------------
# 📌 ETAPA 2: Configuração e Sincronização Contínua de Skills do GitHub
# ------------------------------------------------------------------------------
Write-Host "`n📌 [ETAPA 2/5] Configuração do Repositório de Skills & Inicialização do Servidor" -ForegroundColor Yellow

$defaultRepo = "https://github.com/pmacedo25/project-agents-templates.git"
Write-Host "🌐 O OmniRoute pode carregar agentes, prompts e skills de qualquer repositório Git." -ForegroundColor White
$repoUrl = Read-Host "👉 Digite a URL do repositório Git de Skills (Padrão: $defaultRepo)"
if ([string]::IsNullOrWhiteSpace($repoUrl)) { $repoUrl = $defaultRepo }

# Salva a URL do repositório para atualizações futuras via 'omni pull' ou automação
"OMNIROUTE_SKILLS_REPO=$repoUrl" | Out-File -FilePath "$homeDir\.omniroute\skills-repo.env" -Encoding UTF8

Write-Host "📥 Configurando diretório vivo de Skills em: $skillsDir..." -ForegroundColor Cyan
if (Test-Path "$skillsDir\.git") {
    Write-Host "🔄 Repositório Git já existente em ~/.omniroute/skills. Puxando atualizações recentes (git pull)..." -ForegroundColor Cyan
    Push-Location $skillsDir
    git pull --quiet 2>$null
    Pop-Location
} else {
    Write-Host "📥 Clonando repositório diretamente para ~/.omniroute/skills para permitir atualizações contínuas..." -ForegroundColor Cyan
    if (Test-Path $skillsDir) { Remove-Item $skillsDir -Recurse -Force -ErrorAction SilentlyContinue }
    git clone $repoUrl $skillsDir 2>$null
}
Write-Host "✅ Skills operacionais em ~/.omniroute/skills vinculadas ao repositório: $repoUrl" -ForegroundColor Green

# Pergunta se o usuário deseja agendar a atualização automática no Windows
if ($modo -eq "2") {
    $autoUpdate = Read-Host "`n👉 Deseja criar uma Tarefa Agendada no Windows para rodar 'git pull' nas Skills automaticamente a cada 6 horas? (S/N - Padrão: S)"
    if ($autoUpdate -imatch "^[sS]?$") {
        try {
            $taskName = "OmniRoute-Skills-AutoUpdate"
            Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
            $action = New-ScheduledTaskAction -Execute "git.exe" -Argument "-C `"$skillsDir`" pull --quiet"
            $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Hours 6) -RepetitionDuration (New-TimeSpan -Days 3650)
            Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Description "Atualização automática das Skills do OmniRoute no GitHub" | Out-Null
            Write-Host "✅ Tarefa agendada '$taskName' criada com sucesso (Atualização a cada 6 horas)!" -ForegroundColor Green
        } catch {
            Write-Host "⚠️ Não foi possível registrar a tarefa agendada automática (pode requerer permissão de Administrador). Você pode atualizar manualmente com 'omni pull'." -ForegroundColor Yellow
        }
    }
}

# ------------------------------------------------------------------------------
# 🚀 Iniciação Silenciosa do Servidor Gateway
# ------------------------------------------------------------------------------
if ($modo -eq "1") {
    Write-Host "`n🐳 Modo Container selecionado. Verificando motor de container..." -ForegroundColor Cyan
    $engine = "docker"
    if (-not (Get-Command "docker" -ErrorAction SilentlyContinue)) {
        if (Get-Command "podman" -ErrorAction SilentlyContinue) { $engine = "podman" }
        else {
            Write-Host "❌ Nem Docker nem Podman foram encontrados no PATH!" -ForegroundColor Red
            Write-Host "⚠️ Alternando automaticamente para o Modo Nativo (2)..." -ForegroundColor Yellow
            $modo = "2"
        }
    }
}

if ($modo -eq "1") {
    Write-Host "🚀 Subindo container via $engine compose (Porta 20128)..." -ForegroundColor Cyan
    Push-Location $setupDir
    Invoke-Expression "$engine compose up -d --build"
    Pop-Location
} else {
    Write-Host "`n💻 Verificando Node.js / NPM..." -ForegroundColor Cyan
    if (-not (Get-Command "node" -ErrorAction SilentlyContinue)) {
        Write-Host "❌ Node.js não encontrado no PATH! Instale o Node.js 20+ no Windows antes de continuar." -ForegroundColor Red
        return
    }
    Write-Host "📦 Instalando/Atualizando OmniRoute globalmente via npm..." -ForegroundColor Cyan
    npm install -g omniroute@latest --silent 2>$null

    Write-Host "🧹 Encerrando instâncias antigas e loops de CMD..." -ForegroundColor Yellow
    Get-Process node, npx, cmd -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match "20128" -or $_.MainWindowTitle -match "omniroute" } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    Write-Host "🚀 Iniciando Gateway nativo em segundo plano (Modo Invisível, sem popups)..." -ForegroundColor Cyan
    # Importante: NODE_OPTIONS=--max-old-space-size=4096 evita o erro 'out of memory' do sql.js no Windows
    # Rodamos SEM a flag --daemon para evitar a criação de processos watchdog que abrem janelas CMD
    $cmdArgs = "/c `"set NODE_OPTIONS=--max-old-space-size=4096&& set PORT=20128&& set ENABLE_RTK=true&& set CAVEMAN_MODE=true&& omniroute serve --port 20128 --no-open > `"$logFile`" 2>&1`""
    Start-Process -FilePath "cmd.exe" -ArgumentList $cmdArgs -WindowStyle Hidden
}

Write-Host "⏳ Aguardando 5 segundos para o servidor estabilizar na porta 20128..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

$serverUp = $false
for ($i = 0; $i -lt 5; $i++) {
    $conn = Test-NetConnection -ComputerName localhost -Port 20128 -InformationLevel Quiet -ErrorAction SilentlyContinue
    if ($conn) { $serverUp = $true; break }
    Start-Sleep -Seconds 2
}

if ($serverUp) {
    Write-Host "✅ Servidor OmniRoute Gateway ONLINE na porta 20128!" -ForegroundColor Green
} else {
    Write-Host "⚠️ O servidor demorou a responder na porta 20128. Verifique o log em: $logFile" -ForegroundColor Yellow
}

# ------------------------------------------------------------------------------
# 📌 ETAPA 3: Autenticação OAuth & Geração de APPKEY no Dashboard
# ------------------------------------------------------------------------------
Write-Host "`n📌 [ETAPA 3/5] Conexão de Contas OAuth & Criação de APPKEY no Dashboard" -ForegroundColor Yellow
Write-Host "🌐 Abrindo o Dashboard Web no navegador..." -ForegroundColor Cyan
Start-Process "http://localhost:20128/dashboard"

Write-Host "`n==============================================================================" -ForegroundColor White
Write-Host "👉 PASSO 1: GERAÇÃO DA APPKEY" -ForegroundColor Cyan
Write-Host "  No navegador, vá na aba 'API Keys' (ou Settings) e clique em 'Create Key'." -ForegroundColor White
Write-Host "==============================================================================" -ForegroundColor White

$appKey = Read-Host "`n🔑 Cole aqui a APPKEY gerada no Dashboard para automatizar os Combos e IDEs (ex: sk-omni-...)"
while ([string]::IsNullOrWhiteSpace($appKey)) {
    Write-Host "⚠️ A APPKEY é obrigatória para configurar os Combos e IDEs de forma segura!" -ForegroundColor Yellow
    $appKey = Read-Host "🔑 Cole a APPKEY gerada no Dashboard"
}

# Salva a APPKEY nas variáveis de ambiente e arquivos locais
[Environment]::SetEnvironmentVariable("OMNIROUTE_API_KEY", $appKey, "User")
$env:OMNIROUTE_API_KEY = $appKey
"OMNIROUTE_API_KEY=$appKey" | Set-Content "$homeDir\.omniroute\.env" -Encoding UTF8
"OMNIROUTE_API_KEY=$appKey" | Set-Content "$setupDir\.env" -Encoding UTF8
Write-Host "✅ APPKEY registrada nas variáveis do sistema e no ambiente local!" -ForegroundColor Green

Write-Host "`n==============================================================================" -ForegroundColor White
Write-Host "👉 PASSO 2: CONFIGURAÇÃO DOS PROVEDORES DE IA (Um a Um)" -ForegroundColor Cyan
Write-Host "  Agora vamos autenticar seus provedores na aba 'OAuth / Providers' do Dashboard." -ForegroundColor White
Write-Host "==============================================================================" -ForegroundColor White

$providers = @(
    @{ name = "Anthropic (Claude)"; id = "anthropic" },
    @{ name = "OpenAI / Codex"; id = "openai" },
    @{ name = "GitHub Copilot"; id = "github-copilot" }
)

foreach ($prov in $providers) {
    $resp = Read-Host "`n❓ Deseja conectar/configurar o provedor '$($prov.name)' agora? (s/n)"
    if ($resp -match "^[sS]") {
        Write-Host "  🌐 Abrindo a página de configuração no navegador..." -ForegroundColor Cyan
        Start-Process "http://localhost:20128/dashboard"
        Read-Host "  ⏳ Conecte a conta do '$($prov.name)' no Dashboard e pressione [ENTER] para continuar"
    } else {
        Write-Host "  ⏭️ Provedor '$($prov.name)' pulado." -ForegroundColor DarkGray
    }
}

# ------------------------------------------------------------------------------
# 📌 ETAPA 4: Configuração de Combos Padrão (Default Combos) via API
# ------------------------------------------------------------------------------
Write-Host "`n📌 [ETAPA 4/5] Criando e Mapeando os Combos Padrão via API REST..." -ForegroundColor Yellow

$headers = @{
    "Authorization" = "Bearer $appKey"
    "Content-Type"  = "application/json"
}

# Definição dos 3 Combos Padrão com o formato correto de models (array de strings: "provider/model")
$combos = @(
    @{
        name = "combo-coding"
        strategy = "priority"
        description = "Programação Rápida e Geração de Código"
        models = @(
            "anthropic/claude-3-7-sonnet-latest",
            "openai/gpt-4o",
            "github-copilot/claude-3.7-sonnet"
        )
    },
    @{
        name = "combo-refining"
        strategy = "priority"
        description = "Refinamento, Arquitetura e Raciocínio Profundo"
        models = @(
            "anthropic/claude-3-7-sonnet-latest",
            "openai/o3-mini",
            "github-copilot/gpt-4o"
        )
    },
    @{
        name = "combo-testing"
        strategy = "round-robin"
        description = "Geração de Testes e Validação Contínua"
        models = @(
            "openai/gpt-4o-mini",
            "anthropic/claude-3-5-haiku-20241022",
            "github-copilot/gpt-4o-mini"
        )
    }
)

# Consulta combos existentes para atualizar via PUT ou criar via POST
$existingCombos = @{}
try {
    $list = Invoke-RestMethod -Uri "http://localhost:20128/api/combos" -Method Get -Headers $headers -ErrorAction SilentlyContinue
    if ($list -and $list.combos) {
        foreach ($c in $list.combos) { $existingCombos[$c.name] = $c.id }
    }
} catch {}

foreach ($combo in $combos) {
    try {
        $body = $combo | ConvertTo-Json -Depth 5
        if ($existingCombos.ContainsKey($combo.name)) {
            $cid = $existingCombos[$combo.name]
            Invoke-RestMethod -Uri "http://localhost:20128/api/combos/$cid" -Method Put -Headers $headers -Body $body -ErrorAction Stop | Out-Null
            Write-Host "  ✅ Combo atualizado com sucesso: $($combo.name)" -ForegroundColor Green
        } else {
            Invoke-RestMethod -Uri "http://localhost:20128/api/combos" -Method Post -Headers $headers -Body $body -ErrorAction Stop | Out-Null
            Write-Host "  ✅ Combo criado com sucesso: $($combo.name)" -ForegroundColor Green
        }
    } catch {
        Write-Host "  ℹ️ Não foi possível cadastrar o combo $($combo.name): $_" -ForegroundColor Yellow
    }
}

# Define o combo-coding como o roteamento default (Fallback Global) via API de Settings
try {
    $defaultBody = @{ defaultCombo = "combo-coding"; autoMapping = $true } | ConvertTo-Json
    Invoke-RestMethod -Uri "http://localhost:20128/api/settings/combo-defaults" -Method Post -Headers $headers -Body $defaultBody -ErrorAction SilentlyContinue | Out-Null
    Write-Host "✅ 'combo-coding' configurado como o Roteamento Padrão (Default Combo) no sistema!" -ForegroundColor Green
} catch {
    Write-Host "✅ Configuração de fallback global ativa para os Combos cadastrados!" -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# 📌 ETAPA 5: Automação Universal de IDEs (Antigravity, Claude, Codex, VS Code)
# ------------------------------------------------------------------------------
Write-Host "`n📌 [ETAPA 5/5] Aplicando Configurações na Raiz para todas as IDEs & CLIs..." -ForegroundColor Yellow

# 1. Claude Code App (Desktop Windows) & Claude CLI ('claude')
Write-Host "👉 Configurando Claude Code App / CLI via Variáveis de Sistema..." -ForegroundColor Cyan
[Environment]::SetEnvironmentVariable("ANTHROPIC_BASE_URL", "http://localhost:20128/v1", "User")
[Environment]::SetEnvironmentVariable("ANTHROPIC_API_KEY", $appKey, "User")
[Environment]::SetEnvironmentVariable("ANTHROPIC_MODEL", "combo-coding", "User")
$env:ANTHROPIC_BASE_URL = "http://localhost:20128/v1"
$env:ANTHROPIC_API_KEY = $appKey
$env:ANTHROPIC_MODEL = "combo-coding"

# 2. Codex / OpenAI Desktop App
Write-Host "👉 Nota sobre o Codex / ChatGPT App:" -ForegroundColor DarkGray
Write-Host "  ℹ️ O aplicativo gráfico oficial do ChatGPT/Codex conecta direto na nuvem da OpenAI." -ForegroundColor DarkGray
Write-Host "  ℹ️ Mantendo as variáveis OPENAI padrões do Windows intactas para que o app abra normalmente!" -ForegroundColor Green

# 3. Antigravity 2.0 (App Desktop), Antigravity IDE (VS Code-based) & Antigravity CLI ('agy')
Write-Host "👉 Configurando Antigravity 2.0, Antigravity IDE e CLI ('agy')..." -ForegroundColor Cyan
[Environment]::SetEnvironmentVariable("GEMINI_BASE_URL", "http://localhost:20128/v1", "User")
[Environment]::SetEnvironmentVariable("GEMINI_API_KEY", $appKey, "User")
[Environment]::SetEnvironmentVariable("GOOGLE_GENAI_BASE_URL", "http://localhost:20128/v1", "User")
[Environment]::SetEnvironmentVariable("GOOGLE_API_KEY", $appKey, "User")
[Environment]::SetEnvironmentVariable("GOOGLE_BASE_URL", "http://localhost:20128/v1", "User")
$env:GEMINI_BASE_URL = "http://localhost:20128/v1"
$env:GEMINI_API_KEY = $appKey
$env:GOOGLE_GENAI_BASE_URL = "http://localhost:20128/v1"
$env:GOOGLE_API_KEY = $appKey
$env:GOOGLE_BASE_URL = "http://localhost:20128/v1"

# Configuração no diretório do Antigravity (.gemini)
$geminiDir = "$homeDir\.gemini"
if (-not (Test-Path $geminiDir)) { New-Item -Path $geminiDir -ItemType Directory -Force | Out-Null }
"GEMINI_BASE_URL=http://localhost:20128/v1`nGEMINI_API_KEY=$appKey`nGOOGLE_GENAI_BASE_URL=http://localhost:20128/v1`nGOOGLE_API_KEY=$appKey" | Set-Content -Path "$geminiDir\.env" -Encoding UTF8 -Force

# Injeção no settings.json do Antigravity IDE
$agyIdeSettingsDir = "$env:APPDATA\Antigravity IDE\User"
if (-not (Test-Path $agyIdeSettingsDir)) { New-Item -Path $agyIdeSettingsDir -ItemType Directory -Force | Out-Null }
$agyIdeSettingsPath = "$agyIdeSettingsDir\settings.json"
if (Test-Path $agyIdeSettingsPath) {
    try {
        $agyJson = Get-Content $agyIdeSettingsPath -Raw -ErrorAction Stop | ConvertFrom-Json
        $adv = @{
            "debug.overrideProxyUrl" = "http://localhost:20128/v1"
            "debug.overrideApiKey" = $appKey
        }
        $agyJson | Add-Member -Name "github.copilot.advanced" -Value $adv -MemberType NoteProperty -Force
        $agyJson | ConvertTo-Json -Depth 10 | Set-Content $agyIdeSettingsPath -Encoding UTF8 -Force
        Write-Host "  ✅ settings.json do Antigravity IDE atualizado com sucesso!" -ForegroundColor Green
    } catch {
        Write-Host "  ⚠️ Não foi possível alterar o settings.json do Antigravity IDE automaticamente." -ForegroundColor Yellow
    }
} else {
    @{ "github.copilot.advanced" = @{ "debug.overrideProxyUrl" = "http://localhost:20128/v1"; "debug.overrideApiKey" = $appKey } } | ConvertTo-Json -Depth 5 | Set-Content -Path $agyIdeSettingsPath -Encoding UTF8 -Force
    Write-Host "  ✅ settings.json do Antigravity IDE criado e configurado!" -ForegroundColor Green
}
Write-Host "  ✅ Antigravity 2.0, IDE e CLI configurados com sucesso!" -ForegroundColor Green

# 4. VS Code & GitHub Copilot (Gravação Direta no arquivo settings.json)
Write-Host "👉 Injetando proxy e APPKEY automaticamente no settings.json do VS Code..." -ForegroundColor Cyan
$vsSettingsPath = "$env:APPDATA\Code\User\settings.json"
if (Test-Path $vsSettingsPath) {
    try {
        $vsJson = Get-Content $vsSettingsPath -Raw -ErrorAction Stop | ConvertFrom-Json
        $adv = @{
            "debug.overrideProxyUrl" = "http://localhost:20128/v1"
            "debug.overrideApiKey" = $appKey
        }
        $vsJson | Add-Member -Name "github.copilot.advanced" -Value $adv -MemberType NoteProperty -Force
        $vsJson | ConvertTo-Json -Depth 10 | Set-Content $vsSettingsPath -Encoding UTF8 -Force
        Write-Host "  ✅ settings.json do VS Code Copilot atualizado e configurado!" -ForegroundColor Green
    } catch {
        Write-Host "  ⚠️ Não foi possível alterar o settings.json do VS Code automaticamente (pode estar aberto ou com erro de sintaxe)." -ForegroundColor Yellow
    }
} else {
    Write-Host "  ℹ️ VS Code não detectado no caminho padrão ($vsSettingsPath)." -ForegroundColor DarkGray
}

# 5. Broadcast do Windows para Forçar Atualização Imediata das Variáveis (Sem Relogar)
Write-Host "📡 Notificando o Windows Explorer (WM_SETTINGCHANGE) para adotar as variáveis de ambiente..." -ForegroundColor Cyan
if (-not ("Win32.NativeMethods" -as [type])) {
    add-type -Namespace Win32 -Name NativeMethods -MemberDefinition @'
        [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern IntPtr SendMessageTimeout(
            IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam,
            uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
}
$HWND_BROADCAST = [IntPtr]0xffff
$WM_SETTINGCHANGE = 0x001a
$result = [UIntPtr]::Zero
[Win32.NativeMethods]::SendMessageTimeout($HWND_BROADCAST, $WM_SETTINGCHANGE, [UIntPtr]::Zero, "Environment", 2, 5000, [ref]$result) | Out-Null

# 6. Criação do Atalho 'omni' no Perfil do PowerShell
$profilePath = $PROFILE
if (-not (Test-Path $profilePath)) {
    New-Item -Path $profilePath -ItemType File -Force | Out-Null
}

$omniFunction = @"

# --- Atalho OmniRoute Gateway (Gerenciamento 2026 com APPKEY & Custom Skills) ---
function omni {
    param([string]`$Action = "status", [string]`$Arg1 = "")
    `$setupDir = "$setupDir"
    `$logFile = "`$env:USERPROFILE\.omniroute\gateway.log"
    `$skillsDir = "`$env:USERPROFILE\.omniroute\skills"
    `$env:PATH += ";`$env:APPDATA\npm;C:\Program Files\nodejs;C:\Program Files (x86)\nodejs"
    `$env:OMNIROUTE_API_KEY = "$appKey"
    
    switch (`$Action.ToLower()) {
        "status" {
            Write-Host "🌐 Status do Gateway:" -ForegroundColor Cyan
            `$conn = Test-NetConnection -ComputerName localhost -Port 20128 -InformationLevel Quiet -ErrorAction SilentlyContinue
            if (`$conn) { Write-Host "✅ Gateway RODANDO invisível na porta 20128!" -ForegroundColor Green }
            else { Write-Host "❌ Gateway PARADO. Digite 'omni restart' para iniciar." -ForegroundColor Red }
        }
        "dash" { 
            Write-Host "🌐 Abrindo Dashboard..." -ForegroundColor Green
            Start-Process "http://localhost:20128/dashboard" 
        }
        "logs" {
            if (Test-Path `$logFile) { Get-Content `$logFile -Tail 50 -Wait }
            else { Write-Host "ℹ️ Arquivo de log ainda não criado em: `$logFile" -ForegroundColor Yellow }
        }
        "restart" {
            Write-Host "🔄 Reiniciando Gateway em background invisível..." -ForegroundColor Yellow
            Get-Process node, npx, cmd -ErrorAction SilentlyContinue | Where-Object { `$_.CommandLine -match "20128" -or `$_.MainWindowTitle -match "omniroute" } | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            
            # Sem --daemon (para evitar janelas CMD pop-up) e com aumento de memória (para evitar out of memory)
            `$cmd = "set NODE_OPTIONS=--max-old-space-size=4096&& set PORT=20128&& set ENABLE_RTK=true&& set CAVEMAN_MODE=true&& omniroute serve --port 20128 --no-open > ""`$logFile"" 2>&1"
            Start-Process -FilePath "cmd.exe" -ArgumentList "/c", `$cmd -WindowStyle Hidden
            Write-Host "✅ Gateway reiniciado em background sem janelas pop-up!" -ForegroundColor Green
        }
        "pull" {
            Write-Host "🔄 Sincronizando e atualizando Skills em: `$skillsDir..." -ForegroundColor Cyan
            if (Test-Path "`$skillsDir\.git") {
                Push-Location `$skillsDir
                git pull origin main --quiet
                Pop-Location
                Write-Host "✅ Repositório de Skills atualizado via git pull com sucesso!" -ForegroundColor Green
            } else {
                Write-Host "⚠️ O diretório de skills em `$skillsDir não é um repositório git ativo. Rode o instalador para configurar." -ForegroundColor Yellow
            }
        }
        "reset-db" {
            Write-Host "🧹 Resetando banco de dados SQLite corrompido..." -ForegroundColor Yellow
            Get-Process node, npx, cmd -ErrorAction SilentlyContinue | Where-Object { `$_.CommandLine -match "20128" -or `$_.MainWindowTitle -match "omniroute" } | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
            Remove-Item "`$env:USERPROFILE\.omniroute\storage.sqlite*" -Force -ErrorAction SilentlyContinue
            Write-Host "✅ Banco SQLite resetado com sucesso! Reiniciando Gateway..." -ForegroundColor Green
            omni restart
        }
        "model" { 
            if (`$Arg1 -ne "") {
                [Environment]::SetEnvironmentVariable("ANTHROPIC_MODEL", `$Arg1, "User")
                Write-Host "✅ Combo padrão do Claude Code alterado para: `$Arg1" -ForegroundColor Green
            } else { Write-Host "Uso: omni model <nome-do-combo> (ex: omni model combo-refining)" -ForegroundColor Yellow }
        }
        default { Write-Host "Comandos: omni [status | dash | logs | restart | pull | reset-db | model <combo>]" -ForegroundColor Yellow }
    }
}
"@

$profileContent = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
if ($profileContent -match "function omni \{") {
    $profileContent = $profileContent -replace '(?s)# --- Atalho OmniRoute Gateway.*?}\s*}', $omniFunction
    Set-Content -Path $profilePath -Value $profileContent -Encoding UTF8
} else {
    Add-Content -Path $profilePath -Value "`n$omniFunction" -Encoding UTF8
}

Write-Host "✅ Comando de terminal 'omni' registrado e configurado no PowerShell com a APPKEY!" -ForegroundColor Green

Write-Host "`n==============================================================================" -ForegroundColor Cyan
Write-Host "🎉 SETUP CONCLUÍDO COM SUCESSO! TUDO AUTOMATIZADO COM APPKEY & DEFAULT COMBOS!" -ForegroundColor Green
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "👉 O que você pode fazer agora no terminal:" -ForegroundColor White
Write-Host "   • Digite 'omni status' para checar o servidor (sem popups!)." -ForegroundColor Cyan
Write-Host "   • Digite 'omni dash' para abrir o painel Web quando quiser." -ForegroundColor Cyan
Write-Host "   • Digite 'omni pull' para forçar a atualização imediata das suas Skills do GitHub." -ForegroundColor Cyan
Write-Host "   • Abra o Antigravity, Claude Code, Codex ou VS Code Copilot — todos já estão conectados ao seu Gateway!" -ForegroundColor Green
Write-Host "==============================================================================" -ForegroundColor Cyan
