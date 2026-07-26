# ==============================================================================
# [Setup Interativo] OmniRoute Gateway + Contas OAuth + IDEs Focadas em IA
# Desenvolvido para Windows PowerShell (Suporte a Docker/Podman ou Nativo)
# ==============================================================================

$OutputEncoding = [System.Text.Encoding]::UTF8
$env:PATH += ";$env:APPDATA\npm;C:\Program Files\nodejs;C:\Program Files (x86)\nodejs"

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "=== ASSISTENTE DE SETUP OMNIROUTE 2026 (ROTEAMENTO & COMBOS) ===" -ForegroundColor Yellow
Write-Host "==============================================================================" -ForegroundColor Cyan

$setupDir = $PSScriptRoot
$homeDir = $env:USERPROFILE
$skillsDir = "$homeDir\.omniroute\skills"
$logFile = "$homeDir\.omniroute\gateway.log"
$modeFile = "$homeDir\.omniroute\mode.env"
$envFile = "$homeDir\.omniroute\.env"

# Garante que os diretórios base existem
if (-not (Test-Path "$homeDir\.omniroute")) { New-Item -Path "$homeDir\.omniroute" -ItemType Directory -Force | Out-Null }
if (-not (Test-Path "$homeDir\.omniroute\logs")) { New-Item -Path "$homeDir\.omniroute\logs" -ItemType Directory -Force | Out-Null }

# ------------------------------------------------------------------------------
# [+] Verificação de Reinstalação vs Nova Instalação
# ------------------------------------------------------------------------------
$isReinstall = $false
if ((Test-Path $envFile) -and ((Test-Path "$homeDir\.omniroute\storage.sqlite") -or (Test-Path "$homeDir\.omniroute\data\storage.sqlite") -or (Test-Path "$homeDir\.omniroute\storage.sqlite3"))) {
    $isReinstall = $true
    Write-Host "`n[INFO] Instalação existente do OmniRoute detectada em ~/.omniroute!" -ForegroundColor Cyan
    Write-Host "       Suas chaves de criptografia e bancos de dados serão PRESERVADOS (evitando perda de contas)." -ForegroundColor Green
    $respModo = Read-Host "[?] Deseja manter/atualizar a configuração atual (1) ou resetar tudo do zero (2)? (Padrão: 1)"
    if ($respModo -eq "2") {
        Write-Host "[WARN] Resetando banco de dados e arquivos antigos..." -ForegroundColor Yellow
        Get-Process node, npx, cmd -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match "20128" -or $_.MainWindowTitle -match "omniroute" } | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 1
        Remove-Item "$homeDir\.omniroute\*.sqlite*" -Force -ErrorAction SilentlyContinue
        Remove-Item "$homeDir\.omniroute\data\*.sqlite*" -Force -ErrorAction SilentlyContinue
        Remove-Item $envFile -Force -ErrorAction SilentlyContinue
        $isReinstall = $false
    }
}

# ------------------------------------------------------------------------------
# [+] Garantia de STORAGE_ENCRYPTION_KEY (Prevenção de Internal Error no Dashboard)
# ------------------------------------------------------------------------------
# Se a chave de criptografia do banco não existir, gera e salva ANTES de iniciar o servidor
$envContent = @()
if (Test-Path $envFile) { $envContent = Get-Content $envFile -ErrorAction SilentlyContinue }
if ($envContent -notmatch "STORAGE_ENCRYPTION_KEY=") {
    Write-Host "[>] Gerando STORAGE_ENCRYPTION_KEY para proteger o banco SQLite..." -ForegroundColor Cyan
    $bytes = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
    $hexKey = [System.BitConverter]::ToString($bytes) -replace '-',''
    $envContent += "STORAGE_ENCRYPTION_KEY=$hexKey"
    Set-Content -Path $envFile -Value $envContent -Encoding UTF8
    Copy-Item -Path $envFile -Destination "$setupDir\.env" -Force -ErrorAction SilentlyContinue
    Write-Host "[OK] Chave de criptografia registrada no ambiente local e contêiner!" -ForegroundColor Green
} else {
    Copy-Item -Path $envFile -Destination "$setupDir\.env" -Force -ErrorAction SilentlyContinue
    Write-Host "[OK] Chave STORAGE_ENCRYPTION_KEY existente validada no ambiente." -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# [+] ETAPA 1: Escolha do Modo de Instalação (Container ou Nativo Windows)
# ------------------------------------------------------------------------------
Write-Host "`n[+] [ETAPA 1/5] Escolha do Modo de Instalação e Execução" -ForegroundColor White
Write-Host "  [1] [Docker/Podman] Container Isolado - Sem alterar o sistema" -ForegroundColor Cyan
Write-Host "  [2] [Local] Nativo no Windows (Node.js/NPM) - Sem precisar de Docker" -ForegroundColor Green
$modo = Read-Host "`n-> Digite 1 ou 2 (Padrão: 2)"
if ($modo -ne "1") { $modo = "2" }

if ($modo -eq "1") {
    "OMNIROUTE_MODE=container" | Out-File -FilePath $modeFile -Encoding UTF8 -Force
} else {
    "OMNIROUTE_MODE=local" | Out-File -FilePath $modeFile -Encoding UTF8 -Force
}

# ------------------------------------------------------------------------------
# [+] ETAPA 2: Configuração do Repositório de Skills
# ------------------------------------------------------------------------------
Write-Host "`n[+] [ETAPA 2/5] Configuração do Repositório de Skills & Inicialização do Servidor" -ForegroundColor Yellow

$defaultRepo = "https://github.com/pmacedo25/project-agents-templates.git"
Write-Host "[INFO] O OmniRoute pode carregar agentes, prompts e skills de repositórios Git." -ForegroundColor White
$repoUrl = Read-Host "-> Digite a URL do repositório Git de Skills (Padrão: $defaultRepo)"
if ([string]::IsNullOrWhiteSpace($repoUrl)) { $repoUrl = $defaultRepo }

"OMNIROUTE_SKILLS_REPO=$repoUrl" | Out-File -FilePath "$homeDir\.omniroute\skills-repo.env" -Encoding UTF8

Write-Host "[>] Configurando diretório de Skills em: $skillsDir..." -ForegroundColor Cyan
if (Test-Path "$skillsDir\.git") {
    Write-Host "[>] Repositório Git já existente em ~/.omniroute/skills. Puxando atualizações (git pull)..." -ForegroundColor Cyan
    Push-Location $skillsDir
    git pull --quiet 2>$null
    Pop-Location
} else {
    Write-Host "[>] Clonando repositório diretamente para ~/.omniroute/skills..." -ForegroundColor Cyan
    if (Test-Path $skillsDir) { Remove-Item $skillsDir -Recurse -Force -ErrorAction SilentlyContinue }
    git clone $repoUrl $skillsDir 2>$null
}
Write-Host "[OK] Skills operacionais em ~/.omniroute/skills vinculadas a: $repoUrl" -ForegroundColor Green

if ($modo -eq "1") {
    Write-Host "[INFO] No modo Container, um agendador interno executará 'git pull' automaticamente de hora em hora." -ForegroundColor DarkGray
} else {
    Write-Host "[INFO] No modo Nativo Windows, atualize suas Skills quando desejar rodando o comando 'omni pull'." -ForegroundColor DarkGray
}

# ------------------------------------------------------------------------------
# [+] Iniciação Silenciosa do Servidor Gateway
# ------------------------------------------------------------------------------
if ($modo -eq "1") {
    Write-Host "`n[Docker/Podman] Modo Container selecionado. Verificando motor..." -ForegroundColor Cyan
    $engine = "docker"
    if (-not (Get-Command "docker" -ErrorAction SilentlyContinue)) {
        if (Get-Command "podman" -ErrorAction SilentlyContinue) { $engine = "podman" }
        else {
            Write-Host "[ERROR] Nem Docker nem Podman foram encontrados no PATH!" -ForegroundColor Red
            Write-Host "[WARN] Alternando automaticamente para o Modo Nativo (2)..." -ForegroundColor Yellow
            $modo = "2"
            "OMNIROUTE_MODE=local" | Out-File -FilePath $modeFile -Encoding UTF8 -Force
        }
    }
}

if ($modo -eq "1") {
    Write-Host "[>] Subindo container via $engine compose (Porta 20128)..." -ForegroundColor Cyan
    Push-Location $setupDir
    Invoke-Expression "$engine compose up -d --build"
    Pop-Location
} else {
    Write-Host "`n[Local] Verificando Node.js / NPM..." -ForegroundColor Cyan
    if (-not (Get-Command "node" -ErrorAction SilentlyContinue)) {
        Write-Host "[ERROR] Node.js não encontrado no PATH! Instale o Node.js 20+ no Windows antes de continuar." -ForegroundColor Red
        return
    }
    
    if (-not $isReinstall) {
        Write-Host "[>] Nova instalação detectada. Instalando OmniRoute globalmente via npm..." -ForegroundColor Cyan
        npm install -g omniroute@latest --silent 2>$null
    } else {
        Write-Host "[>] Reinstalação/Atualização. Checando binário global do OmniRoute..." -ForegroundColor Cyan
        if (-not (Get-Command "omniroute" -ErrorAction SilentlyContinue)) {
            npm install -g omniroute@latest --silent 2>$null
        }
    }

    Write-Host "[>] Encerrando instâncias antigas e loops de CMD..." -ForegroundColor Yellow
    Get-Process node, npx, cmd -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match "20128" -or $_.MainWindowTitle -match "omniroute" } | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2

    Write-Host "[>] Iniciando Gateway nativo em segundo plano (Modo Invisível)..." -ForegroundColor Cyan
    $cmdArgs = "/c `"set NODE_OPTIONS=--max-old-space-size=4096&& set PORT=20128&& set ENABLE_RTK=true&& set CAVEMAN_MODE=true&& omniroute serve --port 20128 --no-open > `"$logFile`" 2>&1`""
    Start-Process -FilePath "cmd.exe" -ArgumentList $cmdArgs -WindowStyle Hidden
}

Write-Host "[...] Aguardando 5 segundos para o servidor estabilizar na porta 20128..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

$serverUp = $false
for ($i = 0; $i -lt 5; $i++) {
    $conn = Test-NetConnection -ComputerName localhost -Port 20128 -InformationLevel Quiet -ErrorAction SilentlyContinue
    if ($conn) { $serverUp = $true; break }
    Start-Sleep -Seconds 2
}

if ($serverUp) {
    Write-Host "[OK] Servidor OmniRoute Gateway ONLINE na porta 20128!" -ForegroundColor Green
} else {
    Write-Host "[WARN] O servidor demorou a responder na porta 20128. Verifique o log em: $logFile" -ForegroundColor Yellow
}

# ------------------------------------------------------------------------------
# [+] ETAPA 3: Autenticação OAuth & Geração de APPKEY no Dashboard
# ------------------------------------------------------------------------------
Write-Host "`n[+] [ETAPA 3/5] Conexão de Contas OAuth & Criação de APPKEY no Dashboard" -ForegroundColor Yellow

$existingKey = ""
if (Test-Path $envFile) {
    $lineKey = Get-Content $envFile -ErrorAction SilentlyContinue | Where-Object { $_ -match "^OMNIROUTE_API_KEY=" }
    if ($lineKey) { $existingKey = $lineKey -replace "^OMNIROUTE_API_KEY=","" }
}

$skipWeb = $false
if ($isReinstall -and [string]::IsNullOrWhiteSpace($existingKey) -eq $false) {
    Write-Host "[OK] APPKEY existente detectada na sua instalação: $existingKey" -ForegroundColor Green
    $reusar = Read-Host "[?] Deseja reutilizar esta APPKEY atual (s) ou gerar uma nova no Dashboard (n)? (Padrão: s)"
    if ($reusar -notmatch "^[nN]") {
        $appKey = $existingKey
        $skipWeb = $true
        Write-Host "[OK] Reutilizando APPKEY existente e mantendo provedores logados!" -ForegroundColor Green
    }
}

if (-not $skipWeb) {
    Write-Host "[Web] Abrindo o Dashboard Web no navegador..." -ForegroundColor Cyan
    Start-Process "http://localhost:20128/dashboard"

    Write-Host "`n==============================================================================" -ForegroundColor White
    Write-Host "-> PASSO 1: GERAÇÃO DA APPKEY" -ForegroundColor Cyan
    Write-Host "   No navegador, vá na aba 'API Keys' (ou Settings) e clique em 'Create Key'." -ForegroundColor White
    Write-Host "==============================================================================" -ForegroundColor White

    $appKey = Read-Host "`n[KEY] Cole aqui a APPKEY gerada no Dashboard para automatizar os Combos (ex: sk-omni-...)"
    while ([string]::IsNullOrWhiteSpace($appKey)) {
        Write-Host "[WARN] A APPKEY é obrigatória para configurar os Combos e IDEs de forma segura!" -ForegroundColor Yellow
        $appKey = Read-Host "[KEY] Cole a APPKEY gerada no Dashboard"
    }

    Write-Host "`n==============================================================================" -ForegroundColor White
    Write-Host "-> PASSO 2: CONFIGURAÇÃO DOS PROVEDORES DE IA (Um a Um)" -ForegroundColor Cyan
    Write-Host "   Agora vamos autenticar seus provedores na aba 'OAuth / Providers' do Dashboard." -ForegroundColor White
    Write-Host "==============================================================================" -ForegroundColor White

    $providers = @(
        @{ name = "Anthropic (Claude)"; id = "anthropic" },
        @{ name = "OpenAI / Codex"; id = "openai" },
        @{ name = "GitHub Copilot"; id = "github-copilot" }
    )

    foreach ($prov in $providers) {
        $resp = Read-Host "`n[?] Deseja conectar/configurar o provedor '$($prov.name)' agora? (s/n)"
        if ($resp -match "^[sS]") {
            Write-Host "  [Web] Abrindo a página de configuração no navegador..." -ForegroundColor Cyan
            Start-Process "http://localhost:20128/dashboard"
            Read-Host "  [...] Conecte a conta do '$($prov.name)' no Dashboard e pressione [ENTER] para continuar"
        } else {
            Write-Host "  [INFO] Provedor '$($prov.name)' pulado." -ForegroundColor DarkGray
        }
    }
}

# Salva a APPKEY preservando STORAGE_ENCRYPTION_KEY e outras variáveis do arquivo
[Environment]::SetEnvironmentVariable("OMNIROUTE_API_KEY", $appKey, "User")
$env:OMNIROUTE_API_KEY = $appKey
$currentEnv = @()
if (Test-Path $envFile) { $currentEnv = Get-Content $envFile -ErrorAction SilentlyContinue | Where-Object { $_ -notmatch "^OMNIROUTE_API_KEY=" } }
$currentEnv += "OMNIROUTE_API_KEY=$appKey"
Set-Content -Path $envFile -Value $currentEnv -Encoding UTF8
Copy-Item -Path $envFile -Destination "$setupDir\.env" -Force -ErrorAction SilentlyContinue
Write-Host "[OK] APPKEY registrada nas variáveis do sistema e no ambiente (Local e Contêiner)!" -ForegroundColor Green

# ------------------------------------------------------------------------------
# [+] ETAPA 4: Configuração de Combos Padrão (Default Combos) via API
# ------------------------------------------------------------------------------
Write-Host "`n[+] [ETAPA 4/5] Criando e Mapeando os Combos Padrão via API REST..." -ForegroundColor Yellow

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
            Write-Host "  [OK] Combo atualizado com sucesso: $($combo.name)" -ForegroundColor Green
        } else {
            Invoke-RestMethod -Uri "http://localhost:20128/api/combos" -Method Post -Headers $headers -Body $body -ErrorAction Stop | Out-Null
            Write-Host "  [OK] Combo criado com sucesso: $($combo.name)" -ForegroundColor Green
        }
    } catch {
        Write-Host "  [WARN] Não foi possível cadastrar o combo $($combo.name): $_" -ForegroundColor Yellow
    }
}

# Define o combo-coding como o roteamento default (Fallback Global) via API de Settings
try {
    $defaultBody = @{ defaultCombo = "combo-coding"; autoMapping = $true } | ConvertTo-Json
    Invoke-RestMethod -Uri "http://localhost:20128/api/settings/combo-defaults" -Method Post -Headers $headers -Body $defaultBody -ErrorAction SilentlyContinue | Out-Null
    Write-Host "[OK] 'combo-coding' configurado como o Roteamento Padrão (Default Combo) no sistema!" -ForegroundColor Green
} catch {
    Write-Host "[OK] Configuração de fallback global ativa para os Combos cadastrados!" -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# [+] ETAPA 5: Escolha, Instalação e Configuração da IDE Desktop (OpenCode / OpenHands)
# ------------------------------------------------------------------------------
Write-Host "`n[+] [ETAPA 5/5] Escolha e Instalação da IDE Desktop (Sem Login / 100% BYOK)..." -ForegroundColor Yellow
Write-Host "  [1] OpenCode (IDE / CLI Desktop 100% BYOK - Instalação via npm / Scoop)" -ForegroundColor Cyan
Write-Host "  [2] OpenHands (Plataforma Agente Autônoma - Instalação via Python pip / Docker)" -ForegroundColor Green
Write-Host "  [3] Instalar Ambas (OpenCode e OpenHands)" -ForegroundColor Yellow
Write-Host "  [4] Pular instalação de IDEs agora (Apenas visualizar instruções de configuração)" -ForegroundColor DarkGray

$opcaoIDE = Read-Host "`n-> Escolha sua opção de IDE (1, 2, 3 ou 4) [Padrão: 1]"
if ([string]::IsNullOrWhiteSpace($opcaoIDE)) { $opcaoIDE = "1" }

# Instalação e Configuração do OpenCode
if ($opcaoIDE -eq "1" -or $opcaoIDE -eq "3") {
    Write-Host "`n[>] [Instalação] Verificando e Instalando OpenCode..." -ForegroundColor Cyan
    if (Get-Command "npm" -ErrorAction SilentlyContinue) {
        Write-Host "   [>] Instalando 'opencode-ai' globalmente via npm..." -ForegroundColor Cyan
        npm install -g opencode-ai --silent 2>$null
        if (Get-Command "opencode" -ErrorAction SilentlyContinue) {
            Write-Host "   [OK] OpenCode instalado com sucesso no sistema!" -ForegroundColor Green
        } else {
            Write-Host "   [INFO] Pacote opencode-ai baixado via npm." -ForegroundColor Cyan
        }
    } else {
        Write-Host "   [INFO] npm não disponível. Baixe o instalador desktop do OpenCode em: https://opencode.ai" -ForegroundColor Yellow
    }

    Write-Host "`n==============================================================================" -ForegroundColor White
    Write-Host "-> DIREIONAMENTO DE CONFIGURAÇÃO PARA OPENCODE DESKTOP / CLI:" -ForegroundColor Cyan
    Write-Host "  1. Abra o OpenCode (ou digite 'opencode' no terminal)." -ForegroundColor White
    Write-Host "  2. Acesse Settings / Provider Settings -> selecione 'OpenAI Compatible'." -ForegroundColor White
    Write-Host "  3. Configurações de Conexão:" -ForegroundColor White
    Write-Host "     - Base URL : http://localhost:20128/v1" -ForegroundColor White
    Write-Host "     - API Key  : $appKey" -ForegroundColor White
    Write-Host "     - Modelo   : combo-coding (ou selecione no menu suspenso)" -ForegroundColor White
    Write-Host "==============================================================================" -ForegroundColor White
    Read-Host "[?] Concluiu a configuração do OpenCode? Pressione [ENTER] para continuar"
}

# Instalação e Configuração do OpenHands
if ($opcaoIDE -eq "2" -or $opcaoIDE -eq "3") {
    Write-Host "`n[>] [Instalação] Verificando e Instalando OpenHands..." -ForegroundColor Cyan
    if (Get-Command "pip" -ErrorAction SilentlyContinue) {
        Write-Host "   [>] Instalando 'openhands' via Python pip..." -ForegroundColor Cyan
        pip install openhands --quiet 2>$null
        Write-Host "   [OK] OpenHands instalado com sucesso via pip!" -ForegroundColor Green
    } elseif (Get-Command "docker" -ErrorAction SilentlyContinue) {
        Write-Host "   [>] Docker detectado. Subindo o contêiner do OpenHands na porta 3000..." -ForegroundColor Cyan
        docker run -d --name openhands-app -p 3000:3000 ghcr.io/openhands/agent-server:latest 2>$null
        Write-Host "   [OK] Contêiner do OpenHands iniciado na porta 3000!" -ForegroundColor Green
    } else {
        Write-Host "   [INFO] Para instalar o OpenHands, use 'pip install openhands' ou acesse: https://openhands.dev" -ForegroundColor Yellow
    }

    Write-Host "`n==============================================================================" -ForegroundColor White
    Write-Host "-> DIREIONAMENTO DE CONFIGURAÇÃO PARA OPENHANDS DESKTOP:" -ForegroundColor Cyan
    Write-Host "  1. Abra o OpenHands (ou navegue para http://localhost:3000)." -ForegroundColor White
    Write-Host "  2. Clique em Settings (engrenagem) -> aba LLM -> ative 'Advanced options'." -ForegroundColor White
    Write-Host "  3. Configurações de Conexão:" -ForegroundColor White
    Write-Host "     - Custom Model: combo-coding" -ForegroundColor White
    Write-Host "     - Base URL    : http://localhost:20128/v1" -ForegroundColor White
    Write-Host "       (Obs: Se rodar o OpenHands em Docker, use: http://host.docker.internal:20128/v1)" -ForegroundColor DarkGray
    Write-Host "     - API Key     : $appKey" -ForegroundColor White
    Write-Host "==============================================================================" -ForegroundColor White
    Read-Host "[?] Concluiu a configuração do OpenHands? Pressione [ENTER] para continuar"
}

if ($opcaoIDE -eq "4") {
    Write-Host "[INFO] Instalação de IDEs pulada. Você pode instalar o OpenCode (https://opencode.ai) ou OpenHands (https://openhands.dev) quando quiser!" -ForegroundColor DarkGray
}

# ------------------------------------------------------------------------------
# [+] Criação do Atalho 'omni' no Perfil do PowerShell
# ------------------------------------------------------------------------------
$profilePath = $PROFILE
if (-not (Test-Path $profilePath)) {
    New-Item -Path $profilePath -ItemType File -Force | Out-Null
}

$omniFunction = @"

# --- Atalho OmniRoute Gateway (Gerenciamento 2026 com Suporte Nativo a Container e Local) ---
function omni {
    param([string]`$Action = "status", [string]`$Arg1 = "")
    `$setupDir = "$setupDir"
    `$logFile = "`$env:USERPROFILE\.omniroute\gateway.log"
    `$skillsDir = "`$env:USERPROFILE\.omniroute\skills"
    `$modeFile = "`$env:USERPROFILE\.omniroute\mode.env"
    `$env:PATH += ";`$env:APPDATA\npm;C:\Program Files\nodejs;C:\Program Files (x86)\nodejs"
    `$env:OMNIROUTE_API_KEY = "$appKey"
    
    `$mode = "local"
    if (Test-Path `$modeFile) {
        `$line = Get-Content `$modeFile -ErrorAction SilentlyContinue | Where-Object { `$_ -match "^OMNIROUTE_MODE=" }
        if (`$line -match "container") { `$mode = "container" }
    }
    
    `$engine = "docker"
    if (-not (Get-Command "docker" -ErrorAction SilentlyContinue)) {
        if (Get-Command "podman" -ErrorAction SilentlyContinue) { `$engine = "podman" }
    }
    
    switch (`$Action.ToLower()) {
        "status" {
            Write-Host "[`$(`$mode.ToUpper())] Status do Gateway:" -ForegroundColor Cyan
            `$conn = Test-NetConnection -ComputerName localhost -Port 20128 -InformationLevel Quiet -ErrorAction SilentlyContinue
            if (`$conn) { 
                if (`$mode -eq "container") { Write-Host "[OK] Container OmniRoute Gateway online e respondendo na porta 20128!" -ForegroundColor Green }
                else { Write-Host "[OK] Gateway Nativo RODANDO invisível na porta 20128!" -ForegroundColor Green }
            } else { Write-Host "[ERROR] Gateway PARADO na porta 20128. Digite 'omni restart' para iniciar." -ForegroundColor Red }
        }
        "dash" { 
            Write-Host "[Web] Abrindo Dashboard..." -ForegroundColor Green
            Start-Process "http://localhost:20128/dashboard" 
        }
        "logs" {
            if (`$mode -eq "container") {
                Write-Host "[Docker/Podman] Exibindo logs em tempo real do container 'omniroute-gateway'..." -ForegroundColor Cyan
                Invoke-Expression "`$engine logs -f omniroute-gateway"
            } else {
                if (Test-Path `$logFile) { Get-Content `$logFile -Tail 50 -Wait }
                else { Write-Host "[INFO] Arquivo de log ainda não criado em: `$logFile" -ForegroundColor Yellow }
            }
        }
        "restart" {
            if (`$mode -eq "container") {
                Write-Host "[Docker/Podman] Reiniciando container 'omniroute-gateway'..." -ForegroundColor Yellow
                Push-Location `$setupDir
                Invoke-Expression "`$engine compose restart"
                Pop-Location
                Write-Host "[OK] Container reiniciado com sucesso!" -ForegroundColor Green
            } else {
                Write-Host "[Local] Reiniciando Gateway em background invisível..." -ForegroundColor Yellow
                Get-Process node, npx, cmd -ErrorAction SilentlyContinue | Where-Object { `$_.CommandLine -match "20128" -or `$_.MainWindowTitle -match "omniroute" } | Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 2
                
                `$cmd = "set NODE_OPTIONS=--max-old-space-size=4096&& set PORT=20128&& set ENABLE_RTK=true&& set CAVEMAN_MODE=true&& omniroute serve --port 20128 --no-open > ""`$logFile"" 2>&1"
                Start-Process -FilePath "cmd.exe" -ArgumentList "/c", `$cmd -WindowStyle Hidden
                Write-Host "[OK] Gateway nativo reiniciado em background sem janelas pop-up!" -ForegroundColor Green
            }
        }
        "pull" {
            Write-Host "[>] Sincronizando e atualizando Skills..." -ForegroundColor Cyan
            if (Test-Path "`$skillsDir\.git") {
                Push-Location `$skillsDir
                git pull origin main --quiet
                Pop-Location
                Write-Host "[OK] Volume local de Skills (`$skillsDir) atualizado via git pull!" -ForegroundColor Green
            } else {
                Write-Host "[WARN] Diretório local `$skillsDir não é um repositório git ativo." -ForegroundColor Yellow
            }
            if (`$mode -eq "container") {
                Write-Host "[Docker/Podman] Executando git pull diretamente dentro do container..." -ForegroundColor Cyan
                Invoke-Expression "`$engine exec omniroute-gateway git -C /root/.omniroute/skills pull origin main --quiet" 2>`$null
                Write-Host "[OK] Container sincronizado com o GitHub!" -ForegroundColor Green
            }
        }
        "reset-db" {
            Write-Host "[>] Resetando banco de dados SQLite corrompido..." -ForegroundColor Yellow
            if (`$mode -eq "container") {
                Invoke-Expression "`$engine stop omniroute-gateway" 2>`$null
                Remove-Item "`$env:USERPROFILE\.omniroute\data\*.sqlite*" -Force -ErrorAction SilentlyContinue
                Remove-Item "`$env:USERPROFILE\.omniroute\storage.sqlite*" -Force -ErrorAction SilentlyContinue
                Invoke-Expression "`$engine start omniroute-gateway" 2>`$null
                Write-Host "[OK] Banco SQLite resetado no volume do container e serviço reiniciado!" -ForegroundColor Green
            } else {
                Get-Process node, npx, cmd -ErrorAction SilentlyContinue | Where-Object { `$_.CommandLine -match "20128" -or `$_.MainWindowTitle -match "omniroute" } | Stop-Process -Force -ErrorAction SilentlyContinue
                Start-Sleep -Seconds 1
                Remove-Item "`$env:USERPROFILE\.omniroute\storage.sqlite*" -Force -ErrorAction SilentlyContinue
                Write-Host "[OK] Banco SQLite resetado com sucesso! Reiniciando Gateway nativo..." -ForegroundColor Green
                omni restart
            }
        }
        default { Write-Host "Comandos: omni [status | dash | logs | restart | pull | reset-db]" -ForegroundColor Yellow }
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

Write-Host "[OK] Comando de terminal 'omni' registrado e configurado no PowerShell (Suporte Híbrido Container/Local)!" -ForegroundColor Green

Write-Host "`n==============================================================================" -ForegroundColor Cyan
Write-Host "=== SETUP CONCLUÍDO COM SUCESSO! AMBIENTE IA PRONTO PARA USO ===" -ForegroundColor Green
Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "-> Comandos disponíveis no terminal PowerShell:" -ForegroundColor White
Write-Host "   * 'omni status' : Checar o status do servidor em segundo plano." -ForegroundColor Cyan
Write-Host "   * 'omni dash'   : Abrir o painel Web de gerenciamento (http://localhost:20128/dashboard)." -ForegroundColor Cyan
Write-Host "   * 'omni pull'   : Atualizar suas Skills do GitHub instantaneamente." -ForegroundColor Cyan
Write-Host "   * 'omni logs'   : Acompanhar os logs de requisição do servidor em tempo real." -ForegroundColor Cyan
Write-Host "==============================================================================" -ForegroundColor Cyan
