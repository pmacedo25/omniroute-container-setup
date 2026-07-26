# Interface — provisionamento desktop

## Resumo

Os módulos desta pasta provisionam OmniRoute, clientes locais e OpenRouterAI.
OpenRouterAI é sempre um processo desktop no host, independentemente do gateway
rodar localmente ou em contêiner.

## Leitura rápida para agentes

- Comece por: `OpenRouterAI.Setup.psm1` para instalação da IDE.
- Orquestração geral: `OmniRoute.Setup.psm1`.
- Evite alterar: persistência do OpenHands ao trabalhar somente na IDE.
- Não abra normalmente: imagens e arquivos Docker quando a mudança for local.
- Validação principal: `.\tests\run-tests.ps1`.

## Responsabilidades

### `OpenRouterAI.Setup.psm1`

- Baixar release privado ou consumir ZIP local.
- Validar arquitetura, SemVer e SHA-256.
- Instalar lado a lado em `%LOCALAPPDATA%\Programs\OpenRouterAI`.
- Gravar configuração sem segredo em `%USERPROFILE%\.openrouterai`.
- Ativar versão atomicamente e criar atalhos por usuário.

Não pertence aqui:

- iniciar ou embutir OmniRoute;
- autenticar providers de modelos;
- armazenar a AppKey em JSON;
- construir o Theia na máquina final.

### `OmniRoute.Setup.psm1`

- Preparar gateway, AppKey, combos e compressão.
- Delegar a instalação desktop ao módulo específico.

## Contratos

- Segredo: variável de usuário `OMNIROUTE_API_KEY`.
- Configuração da IDE: `%USERPROFILE%\.openrouterai\config.json`.
- Executável: exatamente um `OpenRouterAI.exe` no artefato.
- Artefato: `OpenRouterAI-win-x64-<semver>.zip`.
- Workspace padrão: `%USERPROFILE%\workspace`.

## Abusos que devem falhar

- Checksum divergente bloqueia ativação.
- Mais de um executável bloqueia o artefato.
- Arquitetura diferente de x64 bloqueia instalação.
- Launcher recusa executável fora da raiz gerenciada.
- Configuração não recebe a AppKey.

## Testes

- `tests/run-tests.ps1`: contratos, sintaxe e regressões do instalador.
- Um release real deve ser validado com instalação, reexecução e rollback em
  conta Windows sem privilégios administrativos.

## Limites de crescimento

Se download, ativação e atalhos ultrapassarem uma responsabilidade legível,
separe-os em módulos próprios em vez de aumentar `OpenRouterAI.Setup.psm1`.
