# Interface — provisionamento desktop

## Resumo

Os módulos desta pasta provisionam OmniRoute, clientes locais e Achilles.
Achilles é sempre um processo desktop no host, independentemente do gateway
rodar em contêiner.

## Leitura rápida para agentes

- Comece por: `Achilles.Setup.psm1` para instalação da IDE.
- Orquestração geral: `OmniRoute.Setup.psm1`.
- Evite alterar: persistência do OmniRoute ao trabalhar somente na IDE.
- Não abra normalmente: imagens e arquivos Docker quando a mudança for local.
- Validação principal: `.\tests\run-tests.ps1`.

## Responsabilidades

### `Achilles.Setup.psm1`

- Baixar release público do repositório de binários ou consumir ZIP local.
- O launcher relê `OMNIROUTE_API_KEY` do ambiente persistente do usuário em
  toda abertura, substituindo valores antigos herdados por processos que
  permaneceram abertos durante uma atualização.
- Validar arquitetura, SemVer e SHA-256.
- Instalar lado a lado em `%LOCALAPPDATA%\Programs\Achilles`.
- Expor a versão ativa pelo junction estável `Programs\Achilles\current` e
  registrar `installDirectory` para a limpeza segura após o reinício.
- Gravar configuração sem segredo em `%USERPROFILE%\.achilles`.
- Copiar de forma aditiva o estado persistente legado em `%USERPROFILE%\.openrouterai`,
  sem caches, layouts transitórios ou launchers da marca anterior.
- Ativar versão atomicamente e criar ou reparar atalhos por usuário, inclusive
  atalhos Achilles já fixados na barra de tarefas.

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
- Configuração da IDE: `%USERPROFILE%\.achilles\config.json`.
- Catálogo: `GET http://127.0.0.1:<porta>/v1/models`, sem allowlist mantida pelo
  instalador.
- Executável: exatamente um `Achilles.exe` no artefato.
- Artefato: `Achilles-win-x64-<semver>.zip`.
- O Achilles não fixa um workspace; cada janela usa as pastas abertas pelo usuário.

## Abusos que devem falhar

- Checksum divergente bloqueia ativação.
- Mais de um executável bloqueia o artefato.
- Arquitetura diferente de x64 bloqueia instalação.
- Launcher recusa executável fora da raiz gerenciada.
- Configuração não recebe a AppKey.
- Migração não remove o estado legado nem sobrescreve o estado novo.

## Testes

- `tests/run-tests.ps1`: contratos, sintaxe e regressões do instalador.
- Um release real deve ser validado com instalação, reexecução e rollback em
  conta Windows sem privilégios administrativos.

## Limites de crescimento

Se download, ativação e atalhos ultrapassarem uma responsabilidade legível,
separe-os em módulos próprios em vez de aumentar `Achilles.Setup.psm1`.
