# ==============================================================================
# Script Windows PowerShell: Conectar IDEs ao Roteador Local
# ==============================================================================

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host "⚙️ Configurando IDEs para usar o Container OmniRoute Local" -ForegroundColor Cyan
Write-Host "Endpoint: http://localhost:20128/v1" -ForegroundColor Yellow
Write-Host "==========================================================" -ForegroundColor Cyan

# 1. Configurando variáveis para Claude Code App / CLI
Write-Host "[1/2] Configurando variáveis de ambiente para o Claude Code App Windows..." -ForegroundColor Green
[Environment]::SetEnvironmentVariable("ANTHROPIC_BASE_URL", "http://localhost:20128", "User")
[Environment]::SetEnvironmentVariable("ANTHROPIC_API_KEY", "ide-account-session", "User")
[Environment]::SetEnvironmentVariable("ANTHROPIC_MODEL", "combo-coding", "User")
Write-Host "✅ ANTHROPIC_BASE_URL e ANTHROPIC_MODEL configurados no seu Usuário Windows!" -ForegroundColor Green

# 2. Configurando variáveis para Codex App / OpenAI
Write-Host "[2/2] Configurando variáveis para Codex App Windows..." -ForegroundColor Green
[Environment]::SetEnvironmentVariable("OPENAI_API_BASE", "http://localhost:20128/v1", "User")
[Environment]::SetEnvironmentVariable("OPENAI_API_KEY", "ide-account-session", "User")
Write-Host "✅ OPENAI_API_BASE configurado com sucesso!" -ForegroundColor Green

Write-Host ""
Write-Host "🎉 Conexão de terminal pronta! Você pode rodar 'claude' ou usar o Codex agora." -ForegroundColor Green
