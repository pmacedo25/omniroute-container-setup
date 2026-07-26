# ==============================================================================
# [Setup Interativo] OmniRoute Gateway + Contas OAuth + IDEs Desktop (OpenHands Container / OpenCode Local)
# Desenvolvido para Windows PowerShell (Suporte Prioritário ao Podman e Docker)
# ==============================================================================

$OutputEncoding = [System.Text.Encoding]::UTF8
$env:PATH += ";C:\Program Files\RedHat\Podman;C:\Program Files\Podman;$env:APPDATA\npm;C:\Program Files\nodejs;C:\Program Files (x86)\nodejs;C:\Python314;C:\Python314\Scripts;$env:USERPROFILE\AppData\Roaming\Python\Scripts"

Write-Host "==============================================================================" -ForegroundColor Cyan
Write-Host "=== ASSISTENTE DE SETUP OMNIROUTE 2026 (PODMAN, COMBOS & AGENTES NATIVOS) ===" -ForegroundColor Yellow
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
# [+] Função de Detecção Prioritária do Motor de Contêiner (Podman em 1º Lugar)
# ------------------------------------------------------------------------------
function Get-ContainerEngine {
    if (Get-Command "podman" -ErrorAction SilentlyContinue) { return "podman" }
    if (Get-Command "docker" -ErrorAction SilentlyContinue) { return "docker" }
    if (Test-Path "C:\Program Files\RedHat\Podman\podman.exe") {
        $env:PATH += ";C:\Program Files\RedHat\Podman"
        return "podman"
    }
    return ""
}

# ------------------------------------------------------------------------------
# [+] ETAPA 1: Escolha do Modo de Instalação (Container ou Nativo Windows)
# ------------------------------------------------------------------------------
Write-Host "`n[+] [ETAPA 1/5] Escolha do Modo de Instalação e Execução" -ForegroundColor White
Write-Host "  [1] [Container (Podman/Docker)] OpenHands + Gateway Isolados [RECOMENDADO PARA OPENHANDS]" -ForegroundColor Cyan
Write-Host "  [2] [Local Nativo Windows] OpenCode Desktop + Gateway via Node.js/NPM" -ForegroundColor Green
$modo = Read-Host "`n-> Digite 1 ou 2 (Padrão: 1)"
if ($modo -ne "2") { $modo = "1" }

if ($modo -eq "1") {
    "OMNIROUTE_MODE=container" | Out-File -FilePath $modeFile -Encoding UTF8 -Force
} else {
    "OMNIROUTE_MODE=local" | Out-File -FilePath $modeFile -Encoding UTF8 -Force
}

# ------------------------------------------------------------------------------
# [+] Tratamento do Banco de Dados (Zero WASM Memory Corruption no Modo Nativo)
# ------------------------------------------------------------------------------
if ($modo -eq "2") {
    Write-Host "`n[>] Modo Nativo Windows selecionado." -ForegroundColor Cyan
    Write-Host "[>] Encerrando instâncias Node antigas e inicializando banco SQLite limpo..." -ForegroundColor Cyan
    Get-CimInstance Win32_Process -Filter "name='node.exe' or name='npx.exe'" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -match "20128" -or $_.CommandLine -match "omniroute" } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
    taskkill /F /IM node.exe 2>$null
    Start-Sleep -Seconds 1
    
    Remove-Item "$homeDir\.omniroute\*.sqlite*" -Force -ErrorAction SilentlyContinue
    Remove-Item "$homeDir\.omniroute\data\*.sqlite*" -Force -ErrorAction SilentlyContinue
}

# ------------------------------------------------------------------------------
# [+] Garantia de STORAGE_ENCRYPTION_KEY Única e Permanente
# ------------------------------------------------------------------------------
$rawEnv = ""
if (Test-Path $envFile) { $rawEnv = Get-Content $envFile -Raw -ErrorAction SilentlyContinue }

if ($rawEnv -notmatch "STORAGE_ENCRYPTION_KEY=") {
    Write-Host "[>] Gerando STORAGE_ENCRYPTION_KEY para proteger o banco SQLite..." -ForegroundColor Cyan
    $bytes = [System.Security.Cryptography.RandomNumberGenerator]::GetBytes(32)
    $hexKey = [System.BitConverter]::ToString($bytes) -replace '-',''
    Add-Content -Path $envFile -Value "`nSTORAGE_ENCRYPTION_KEY=$hexKey" -Encoding UTF8
    Copy-Item -Path $envFile -Destination "$setupDir\.env" -Force -ErrorAction SilentlyContinue
    Write-Host "[OK] Chave de criptografia única registrada no ambiente!" -ForegroundColor Green
} else {
    Copy-Item -Path $envFile -Destination "$setupDir\.env" -Force -ErrorAction SilentlyContinue
    Write-Host "[OK] Chave STORAGE_ENCRYPTION_KEY permanente validada." -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# [+] ETAPA 2: Configuração do Repositório de Skills
# ------------------------------------------------------------------------------
Write-Host "`n[+] [ETAPA 2/5] Configuração do Repositório de Skills & Inicialização do Servidor" -ForegroundColor Yellow

$defaultRepo = "https://github.com/pmacedo25/project-agents-templates.git"
Write-Host "[INFO] O OmniRoute carrega agentes, prompts e skills de repositórios Git." -ForegroundColor White
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

# ------------------------------------------------------------------------------
# [+] ETAPA 3: Iniciação do Servidor Gateway
# ------------------------------------------------------------------------------
if ($modo -eq "1") {
    Write-Host "`n[Container] Verificando motor de contêiner (Podman em 1º Lugar)..." -ForegroundColor Cyan
    $engine = Get-ContainerEngine
    
    if ([string]::IsNullOrWhiteSpace($engine)) {
        Write-Host "[WARN] Nem Podman nem Docker foram encontrados no PATH!" -ForegroundColor Yellow
        $instPodman = Read-Host "[?] Deseja instalar o Podman Desktop via winget agora? (s/n - Padrão: s)"
        if ($instPodman -notmatch "^[nN]") {
            if (Get-Command "winget" -ErrorAction SilentlyContinue) {
                Write-Host "   [>] Baixando e instalando Podman Desktop via winget..." -ForegroundColor Cyan
                winget install -e --id RedHat.Podman-Desktop 2>&1 | Out-Null
                $engine = Get-ContainerEngine
            }
        }
        
        if ([string]::IsNullOrWhiteSpace($engine)) {
            Write-Host "[WARN] Alternando automaticamente para o Modo Nativo Windows (2)..." -ForegroundColor Yellow
            $modo = "2"
            "OMNIROUTE_MODE=local" | Out-File -FilePath $modeFile -Encoding UTF8 -Force
        }
    }
}

if ($modo -eq "1") {
    Write-Host "[OK] Motor de contêiner detectado: $engine" -ForegroundColor Green
    Write-Host "[>] Subindo contêiner via $engine compose (Porta 20128)..." -ForegroundColor Cyan
    Push-Location $setupDir
    Invoke-Expression "$engine compose up -d --build"
    Pop-Location
} else {
    Write-Host "`n[Local] Verificando Node.js / NPM..." -ForegroundColor Cyan
    if (-not (Get-Command "node" -ErrorAction SilentlyContinue)) {
        Write-Host "[ERROR] Node.js não encontrado no PATH! Instale o Node.js 20+ no Windows antes de continuar." -ForegroundColor Red
        return
    }

    Write-Host "[>] Instalando/Atualizando OmniRoute globalmente via npm..." -ForegroundColor Cyan
    npm install -g omniroute@latest --silent 2>$null

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
# [+] ETAPA 4: Autenticação OAuth & Geração de APPKEY no Dashboard
# ------------------------------------------------------------------------------
Write-Host "`n[+] [ETAPA 4/5] Conexão de Contas OAuth & Criação de APPKEY no Dashboard" -ForegroundColor Yellow

Write-Host "[Web] Abrindo o Dashboard Web no navegador..." -ForegroundColor Cyan
Start-Process "http://localhost:20128/dashboard"

Write-Host "`n==============================================================================" -ForegroundColor White
Write-Host "-> PASSO 1: GERAÇÃO DA APPKEY" -ForegroundColor Cyan
Write-Host "   No navegador, vá na aba 'API Keys' (ou Settings) e clique em 'Create Key'." -ForegroundColor White
Write-Host "==============================================================================" -ForegroundColor White

$appKey = Read-Host "`n[KEY] Cole aqui a APPKEY gerada no Dashboard (ex: sk-omni-...)"
while ([string]::IsNullOrWhiteSpace($appKey)) {
    Write-Host "[WARN] A APPKEY é obrigatória para configurar os Combos e IDEs de forma segura!" -ForegroundColor Yellow
    $appKey = Read-Host "[KEY] Cole a APPKEY gerada no Dashboard"
}

Write-Host "`n==============================================================================" -ForegroundColor White
Write-Host "-> PASSO 2: AUTENTICAÇÃO DOS SEUS PROVEDORES DE IA" -ForegroundColor Cyan
Write-Host "   Abrindo o Dashboard na aba de Provedores/OAuth..." -ForegroundColor White
Write-Host "   No navegador, conecte as contas dos provedores que você possui (Claude, OpenAI, Copilot, etc.)." -ForegroundColor White
Write-Host "==============================================================================" -ForegroundColor White
Start-Process "http://localhost:20128/dashboard"
Read-Host "`n[?] Após conectar seus provedores no Dashboard, pressione [ENTER] para continuar"

[Environment]::SetEnvironmentVariable("OMNIROUTE_API_KEY", $appKey, "User")
$env:OMNIROUTE_API_KEY = $appKey

$currentEnvLines = @()
if (Test-Path $envFile) { $currentEnvLines = Get-Content $envFile -ErrorAction SilentlyContinue | Where-Object { $_ -notmatch "^OMNIROUTE_API_KEY=" } }
$currentEnvLines += "OMNIROUTE_API_KEY=$appKey"
Set-Content -Path $envFile -Value $currentEnvLines -Encoding UTF8
Copy-Item -Path $envFile -Destination "$setupDir\.env" -Force -ErrorAction SilentlyContinue
Write-Host "[OK] APPKEY registrada no ambiente!" -ForegroundColor Green

# ------------------------------------------------------------------------------
# [+] Mapeamento de Combos Padrão via API REST
# ------------------------------------------------------------------------------
Write-Host "`n[>] Criando e Mapeando os Combos Padrão via API REST..." -ForegroundColor Yellow

$headers = @{
    "Authorization" = "Bearer $appKey"
    "Content-Type"  = "application/json"
}

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

try {
    $defaultBody = @{ defaultCombo = "combo-coding"; autoMapping = $true } | ConvertTo-Json
    Invoke-RestMethod -Uri "http://localhost:20128/api/settings/combo-defaults" -Method Post -Headers $headers -Body $defaultBody -ErrorAction SilentlyContinue | Out-Null
    Write-Host "[OK] 'combo-coding' configurado como Roteamento Padrão!" -ForegroundColor Green
} catch {}

# ------------------------------------------------------------------------------
# [+] ETAPA 5: Instalação Automática da IDE/Agente Desktop Específico por Modo
# ------------------------------------------------------------------------------
Write-Host "`n[+] [ETAPA 5/5] Configuração da IDE/Agente Desktop (OpenHands no Container / OpenCode no Local)" -ForegroundColor Yellow

if ($modo -eq "1") {
    # --------------------------------------------------------------------------
    # MODO CONTAINER: Configuração e Lançamento do OpenHands via Podman/Docker
    # --------------------------------------------------------------------------
    Write-Host "[>] Configurando OpenHands no Modo Container via $engine..." -ForegroundColor Cyan
    
    $openhandsDir = "$homeDir\.openhands"
    $binDir = "$openhandsDir\bin"
    if (-not (Test-Path $binDir)) { New-Item -Path $binDir -ItemType Directory -Force | Out-Null }

    $openhandsConfig = @{
        llm = @{
            model = "combo-coding"
            base_url = "http://localhost:20128/v1"
            api_key = $appKey
        }
    } | ConvertTo-Json -Depth 5

    Set-Content -Path "$openhandsDir\agent_settings.json" -Value $openhandsConfig -Encoding UTF8
    [Environment]::SetEnvironmentVariable("LLM_MODEL", "combo-coding", "User")
    [Environment]::SetEnvironmentVariable("LLM_BASE_URL", "http://localhost:20128/v1", "User")
    [Environment]::SetEnvironmentVariable("LLM_API_KEY", $appKey, "User")
    Write-Host "  [OK] Configuração de LLM injetada em ~/.openhands/agent_settings.json!" -ForegroundColor Green

    # Subida do Contêiner do OpenHands via Podman ou Docker
    Write-Host "  [>] Subindo contêiner do OpenHands na porta 3000 via $engine..." -ForegroundColor Cyan
    Invoke-Expression "$engine run -d --name openhands-app -p 3000:3000 -e LLM_MODEL=combo-coding -e LLM_BASE_URL=http://localhost:20128/v1 -e LLM_API_KEY=$appKey ghcr.io/openhands/agent-server:latest" 2>$null

    # Lançador Autônomo do OpenHands Desktop
    $launcherCmd = @"
@echo off
set "PATH=%PATH%;C:\Program Files\RedHat\Podman;C:\Program Files\Podman"

powershell -NoProfile -Command "Test-NetConnection -ComputerName localhost -Port 3000 -InformationLevel Quiet" | findstr /i "True" >nul 2>&1
if errorlevel 1 (
    echo [OpenHands Desktop App] Garantindo contêiner do agente rodando na porta 3000...
    podman start openhands-app 2>nul || docker start openhands-app 2>nul || podman run -d --name openhands-app -p 3000:3000 ghcr.io/openhands/agent-server:latest 2>nul || docker run -d --name openhands-app -p 3000:3000 ghcr.io/openhands/agent-server:latest 2>nul
    powershell -NoProfile -Command "for (`$i=0; `$i -lt 15; `$i++) { if (Test-NetConnection -ComputerName localhost -Port 3000 -InformationLevel Quiet) { exit 0 }; Start-Sleep -Seconds 1 }; exit 1"
)

set "APP_BROWSER=msedge.exe"
where msedge.exe >nul 2>&1
if errorlevel 1 set "APP_BROWSER=chrome.exe"

start "" %APP_BROWSER% --app=http://localhost:3000 --user-data-dir="%USERPROFILE%\.openhands\app_profile"
"@
    Set-Content -Path "$binDir\openhands-app.cmd" -Value $launcherCmd -Encoding UTF8

    try {
        $wsh = New-Object -ComObject WScript.Shell
        $desktopPath = [System.Environment]::GetFolderPath('Desktop')
        $startMenuPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
        
        foreach ($dest in @("$desktopPath\OpenHands Desktop.lnk", "$startMenuPath\OpenHands Desktop.lnk")) {
            $sc = $wsh.CreateShortcut($dest)
            $sc.TargetPath = "$binDir\openhands-app.cmd"
            $sc.WindowStyle = 7
            $sc.IconLocation = "msedge.exe,0"
            $sc.Description = "OpenHands Desktop AI Agent App (Podman/Docker)"
            $sc.Save()
        }
        Write-Host "  [OK] Aplicativo 'OpenHands Desktop' registrado na Área de Trabalho!" -ForegroundColor Green
    } catch {}

    Write-Host "  [App] Serviço ONLINE na porta 3000! Abrindo o aplicativo OpenHands Desktop..." -ForegroundColor Green
    Start-Process -FilePath "$binDir\openhands-app.cmd" -WindowStyle Hidden

} else {
    # --------------------------------------------------------------------------
    # MODO LOCAL NATIVO WINDOWS: Configuração e Instalação do OpenCode Desktop
    # --------------------------------------------------------------------------
    Write-Host "[>] Configurando OpenCode Desktop para Modo Local Nativo..." -ForegroundColor Cyan
    if (Get-Command "npm" -ErrorAction SilentlyContinue) {
        Write-Host "   [>] Instalando 'opencode-ai' globalmente via npm..." -ForegroundColor Cyan
        npm install -g opencode-ai --silent 2>$null
    }

    $opencodeDirs = @("$homeDir\.opencode", "$env:APPDATA\opencode")
    foreach ($dir in $opencodeDirs) {
        if (-not (Test-Path $dir)) { New-Item -Path $dir -ItemType Directory -Force | Out-Null }
        $opencodeConfig = @{
            provider = "openai-compatible"
            baseUrl = "http://localhost:20128/v1"
            apiKey = $appKey
            model = "combo-coding"
        } | ConvertTo-Json -Depth 5
        Set-Content -Path "$dir\config.json" -Value $opencodeConfig -Encoding UTF8
    }
    Write-Host "  [OK] Configuração injetada em ~/.opencode/config.json e APPDATA!" -ForegroundColor Green

    # Criação do Atalho Desktop do OpenCode
    try {
        $wsh = New-Object -ComObject WScript.Shell
        $desktopPath = [System.Environment]::GetFolderPath('Desktop')
        $startMenuPath = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs"
        
        $opencodeBin = (Get-Command "opencode" -ErrorAction SilentlyContinue).Source
        if ([string]::IsNullOrWhiteSpace($opencodeBin)) { $opencodeBin = "$env:APPDATA\npm\opencode.cmd" }

        foreach ($dest in @("$desktopPath\OpenCode Desktop.lnk", "$startMenuPath\OpenCode Desktop.lnk")) {
            $sc = $wsh.CreateShortcut($dest)
            $sc.TargetPath = $opencodeBin
            $sc.Description = "OpenCode Desktop AI Agent App"
            $sc.Save()
        }
        Write-Host "  [OK] Aplicativo 'OpenCode Desktop' registrado na Área de Trabalho!" -ForegroundColor Green
    } catch {}

    Write-Host "  [App] OpenCode pronto para uso! Digite 'opencode' no terminal ou abra o atalho na Área de Trabalho." -ForegroundColor Green
}

# ------------------------------------------------------------------------------
# [+] Criação do Atalho 'omni' no Perfil do PowerShell
# ------------------------------------------------------------------------------
$profilePath = $PROFILE
if (-not (Test-Path $profilePath)) {
    New-Item -Path $profilePath -ItemType File -Force | Out-Null
}

$omniFunction = @"

# --- Atalho OmniRoute Gateway (Gerenciamento 2026 com Suporte Prioritário ao Podman e Docker) ---
function omni {
    param([string]`$Action = "status", [string]`$Arg1 = "")
    `$setupDir = "$setupDir"
    `$logFile = "`$env:USERPROFILE\.omniroute\gateway.log"
    `$skillsDir = "`$env:USERPROFILE\.omniroute\skills"
    `$modeFile = "`$env:USERPROFILE\.omniroute\mode.env"
    `$env:PATH += ";C:\Program Files\RedHat\Podman;C:\Program Files\Podman;`$env:APPDATA\npm;C:\Program Files\nodejs;C:\Program Files (x86)\nodejs;C:\Python314;C:\Python314\Scripts;`$env:USERPROFILE\AppData\Roaming\Python\Scripts"
    `$env:OMNIROUTE_API_KEY = "$appKey"
    
    `$mode = "local"
    if (Test-Path `$modeFile) {
        `$line = Get-Content `$modeFile -ErrorAction SilentlyContinue | Where-Object { `$_ -match "^OMNIROUTE_MODE=" }
        if (`$line -match "container") { `$mode = "container" }
    }
    
    `$engine = "docker"
    if (Get-Command "podman" -ErrorAction SilentlyContinue) { `$engine = "podman" }
    elseif (Test-Path "C:\Program Files\RedHat\Podman\podman.exe") { `$engine = "podman" }
    
    switch (`$Action.ToLower()) {
        "status" {
            Write-Host "[`$(`$mode.ToUpper())] Status do Gateway (Motor: `$engine):" -ForegroundColor Cyan
            `$conn = Test-NetConnection -ComputerName localhost -Port 20128 -InformationLevel Quiet -ErrorAction SilentlyContinue
            if (`$conn) { 
                if (`$mode -eq "container") { Write-Host "[OK] Contêiner OmniRoute Gateway online e respondendo na porta 20128 via `$engine!" -ForegroundColor Green }
                else { Write-Host "[OK] Gateway Nativo RODANDO invisível na porta 20128!" -ForegroundColor Green }
            } else { Write-Host "[ERROR] Gateway PARADO na porta 20128. Digite 'omni restart' para iniciar." -ForegroundColor Red }
        }
        "dash" { 
            Write-Host "[Web] Abrindo Dashboard..." -ForegroundColor Green
            Start-Process "http://localhost:20128/dashboard" 
        }
        "logs" {
            if (`$mode -eq "container") {
                Write-Host "[`$engine] Exibindo logs em tempo real do container 'omniroute-gateway'..." -ForegroundColor Cyan
                Invoke-Expression "`$engine logs -f omniroute-gateway"
            } else {
                if (Test-Path `$logFile) { Get-Content `$logFile -Tail 50 -Wait }
                else { Write-Host "[INFO] Arquivo de log ainda não criado em: `$logFile" -ForegroundColor Yellow }
            }
        }
        "restart" {
            if (`$mode -eq "container") {
                Write-Host "[`$engine] Reiniciando container 'omniroute-gateway'..." -ForegroundColor Yellow
                Push-Location `$setupDir
                Invoke-Expression "`$engine compose restart"
                Pop-Location
                Write-Host "[OK] Container reiniciado com sucesso via `$engine!" -ForegroundColor Green
            } else {
                Write-Host "[Local] Reiniciando Gateway em background invisível..." -ForegroundColor Yellow
                Get-CimInstance Win32_Process -Filter "name='node.exe' or name='npx.exe'" -ErrorAction SilentlyContinue | Where-Object { `$_.CommandLine -match "20128" -or `$_.CommandLine -match "omniroute" } | ForEach-Object { Stop-Process -Id `$_.ProcessId -Force -ErrorAction SilentlyContinue }
                taskkill /F /IM node.exe 2>`$null
                Start-Sleep -Seconds 2
                
                `$cmd = "set NODE_OPTIONS=--max-old-space-size=4096&& set PORT=20128&& set ENABLE_RTK=true&& set CAVEMAN_MODE=true&& omniroute serve --port 20128 --no-open > ""`$logFile"" 2>&1"
                Start-Process -FilePath "cmd.exe" -ArgumentList "/c", `$cmd -WindowStyle Hidden
                Write-Host "[OK] Gateway nativo reiniciado em background!" -ForegroundColor Green
            }
        }
        "pull" {
            Write-Host "[>] Sincronizando e atualizando Skills..." -ForegroundColor Cyan
            if (Test-Path "`$skillsDir\.git") {
                Push-Location `$skillsDir
                git pull origin main --quiet
                Pop-Location
                Write-Host "[OK] Volume local de Skills (`$skillsDir) atualizado via git pull!" -ForegroundColor Green
            }
            if (`$mode -eq "container") {
                Write-Host "[`$engine] Executando git pull diretamente dentro do container..." -ForegroundColor Cyan
                Invoke-Expression "`$engine exec omniroute-gateway git -C /root/.omniroute/skills pull origin main --quiet" 2>`$null
                Write-Host "[OK] Container sincronizado com o GitHub!" -ForegroundColor Green
            }
        }
        "reset-db" {
            Write-Host "[>] Resetando banco de dados SQLite..." -ForegroundColor Yellow
            if (`$mode -eq "container") {
                Invoke-Expression "`$engine stop omniroute-gateway" 2>`$null
                Remove-Item "`$env:USERPROFILE\.omniroute\data\*.sqlite*" -Force -ErrorAction SilentlyContinue
                Remove-Item "`$env:USERPROFILE\.omniroute\storage.sqlite*" -Force -ErrorAction SilentlyContinue
                Invoke-Expression "`$engine start omniroute-gateway" 2>`$null
                Write-Host "[OK] Banco SQLite resetado no volume do container e serviço reiniciado!" -ForegroundColor Green
            } else {
                Get-CimInstance Win32_Process -Filter "name='node.exe' or name='npx.exe'" -ErrorAction SilentlyContinue | Where-Object { `$_.CommandLine -match "20128" -or `$_.CommandLine -match "omniroute" } | ForEach-Object { Stop-Process -Id `$_.ProcessId -Force -ErrorAction SilentlyContinue }
                taskkill /F /IM node.exe 2>`$null
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

Write-Host "[OK] Comando 'omni' atualizado no PowerShell com suporte prioritário ao Podman!" -ForegroundColor Green

Write-Host "`n==============================================================================" -ForegroundColor Cyan
Write-Host "=== SETUP CONCLUÍDO COM SUCESSO! AMBIENTE IA PRONTO PARA USO ===" -ForegroundColor Green
Write-Host "==============================================================================" -ForegroundColor Cyan
