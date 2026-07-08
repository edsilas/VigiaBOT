# Changelog

Todas as mudanças relevantes deste projeto são documentadas neste arquivo.

O formato segue [Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/)
e o projeto adota o [Versionamento Semântico](https://semver.org/lang/pt-BR/).

## [1.0.1] - 2026-07-08

Correção de confiabilidade do robô de comandos do Telegram, sem alteração ou
remoção de funcionalidades existentes (sem regressões).

### Corrigido

- **Robô de comandos do Telegram** (`Monitor-Bot.ps1`) não respondia quando os
  segredos eram definidos pelo modo padrão do assistente ("Arquivo de
  configuração"). O bot lia o token apenas da variável de ambiente
  `MONITOR_TG_TOKEN` (ou do valor inline) e ignorava o `MonitorConfig.json`,
  ao contrário do `Monitor.ps1`. Nessa situação o bot iniciava sem token
  válido e encerrava, enquanto os alertas do monitor continuavam funcionando.
  Agora o bot lê o mesmo `MonitorConfig.json` e dele obtém o token, os Chat IDs
  autorizados (por união, sem remover IDs já configurados), os serviços
  críticos e o nome da tarefa. A variável de ambiente e os valores inline
  continuam válidos.
- Caminho do log lido por `/log` deixou de ser fixo em
  `C:\Monitoramento\logs\monitor.log` e passou a ser resolvido de forma robusta
  (a partir do `LogDir` do JSON ou do diretório de instalação real), evitando a
  mensagem "log ainda não gerado" quando a instalação fica em outro diretório.
- `Send-Reply` agora registra o motivo de uma recusa do Telegram e, se o envio
  em HTML falhar, reenvia a resposta em texto simples, evitando respostas
  perdidas silenciosamente.
- Linha de diagnóstico no início do log do bot indicando a origem da
  configuração (JSON, variável de ambiente ou inline) e o caminho do log do
  monitor, para facilitar o suporte.

## [1.0.0] - 2026-07-04

Primeira versão pública do **VigiaBOT**. Consolida o agente de monitoramento,
o listener de comandos do Telegram e o assistente interativo de implantação
em um único projeto documentado e pronto para uso em campo.

### Adicionado

- **Agente de monitoramento** (`Monitor.ps1`): coleta de CPU, RAM, disco, rede,
  serviços, eventos críticos, processos travados, reinicializações inesperadas,
  BSOD e falhas de Backup/Windows Update/Banco de Dados, com envio de alertas
  inteligentes via Telegram.
- **Estado persistente** entre execuções (CPU sustentada, cooldown de alertas,
  último boot) em arquivo JSON, evitando spam de notificações.
- **Override externo de configuração** via `MonitorConfig.json`, permitindo
  parametrizar todo o comportamento sem editar o código do agente.
- **Listener de comandos do Telegram** (`Monitor-Bot.ps1`): comandos somente
  leitura `/status`, `/check`, `/log`, `/servicos`, `/disco`, `/uptime` e
  `/help`, restritos a Chat IDs autorizados, com instância única (mutex) para
  evitar conflito 409 no `getUpdates`.
- **Instalador de tarefa agendada** (`Install-Monitor.ps1`): registra a tarefa
  na conta `SYSTEM` (gatilhos de 5 minutos e de boot), com opções
  `-Install`, `-Uninstall` e `-Test`.
- **Assistente interativo de implantação — Launcher** (`Launcher-Monitoramento.ps1`):
  - Implantação Expressa que encadeia todas as etapas de ponta a ponta.
  - Configuração do Telegram com validação de token ao vivo (`getMe`) e
    **detecção automática do Chat ID** via `getUpdates` (privado e grupo).
  - Parametrização inteligente que inspeciona a máquina (núcleos, RAM, papel do
    servidor, discos, serviços) e sugere limiares e serviços críticos sob medida
    (SQL Server, MySQL, PostgreSQL, Oracle, IIS).
  - Preparo de ambiente: firewall para a porta 443 (inclusive `pwsh.exe`),
    TLS 1.2, política de execução e teste de conectividade.
  - Painel de status e rollback/remoção assistidos.
  - Dois modos de guarda de segredos: arquivo de configuração ou variável de
    ambiente de máquina.
- **Bootstrapper de duplo-clique** (`INICIAR-Assistente.cmd`) com auto-elevação
  via UAC e detecção automática do runtime (`pwsh` ou `powershell.exe`).
- **Scripts auxiliares**: `Preparar-Ambiente.cmd`, `Atualizar-Agendador.cmd` e
  `Agendar-Bot.cmd`.
- **Documentação técnica**: `README.md`, manual completo, guia de campo,
  guia de configuração e guia do assistente.
- **Definição da tarefa** em `MonitoramentoServidor.xml` (gatilhos de tempo e
  boot, conta `SYSTEM`, privilégios máximos, reinício em falha).

### Segurança

- Remoção das credenciais reais do Telegram (token e Chat ID) que estavam
  embutidas como valores padrão no código; substituídas por marcadores de
  preenchimento. Os segredos passam a ser fornecidos por variável de ambiente
  ou pelo `MonitorConfig.json`.
- `.gitignore` configurado para impedir o versionamento acidental de
  `MonitorConfig.json`, logs, estado e backups.

### Compatibilidade

- Windows Server 2012 R2, 2016, 2019, 2022 e Windows 10/11.
- Windows PowerShell 5.1 e PowerShell 7 (pwsh).
- Código do agente independente de idioma do SO (contadores CIM/WMI) e sem
  dependências externas.

[1.0.1]: https://github.com/edsilas/VigiaBOT/releases/tag/v1.0.1
[1.0.0]: https://github.com/edsilas/VigiaBOT/releases/tag/v1.0.0
