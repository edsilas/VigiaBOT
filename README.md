<div align="center">

# 🛡️ VigiaBOT

**Monitoramento inteligente de servidores Windows com alertas via Telegram e assistente interativo de implantação.**

[![Licença](https://img.shields.io/badge/licen%C3%A7a-Apache%202.0-blue.svg)](LICENSE)
[![Versão](https://img.shields.io/badge/vers%C3%A3o-1.0.1-green.svg)](CHANGELOG.md)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1%20%7C%207-5391FE.svg)](#requisitos)
[![Plataforma](https://img.shields.io/badge/Windows-Server%202012R2%2B%20%7C%2010%2F11-0078D6.svg)](#requisitos)

</div>

---

## 📑 Sumário

- [Apresentação](#-apresentação)
- [Visão geral](#-visão-geral)
- [Principais funcionalidades](#-principais-funcionalidades)
- [Objetivos do projeto](#-objetivos-do-projeto)
- [Recursos disponíveis](#-recursos-disponíveis)
- [Requisitos](#-requisitos)
- [Instalação](#-instalação)
- [Configuração](#-configuração)
- [Guia de utilização](#-guia-de-utilização)
- [Estrutura do projeto](#-estrutura-do-projeto)
- [Arquitetura da solução](#-arquitetura-da-solução)
- [Tecnologias utilizadas](#-tecnologias-utilizadas)
- [Boas práticas](#-boas-práticas)
- [Roadmap](#-roadmap)
- [Contribuição](#-contribuição)
- [Changelog](#-changelog)
- [Licença](#-licença)
- [Créditos](#-créditos)

---

## 🎯 Apresentação

O **VigiaBOT** é uma solução de monitoramento para servidores **Windows** que
observa continuamente a saúde da máquina — CPU, memória, disco, rede, serviços,
eventos críticos e ocorrências inesperadas — e **notifica o responsável em tempo
real pelo Telegram**, sem necessidade de painéis pagos, agentes pesados ou
dependências externas.

Além do agente de coleta, o VigiaBOT inclui um **assistente interativo de
implantação (Launcher)** que transforma a instalação em campo em uma experiência
guiada: valida credenciais, detecta o Chat ID automaticamente, sugere limiares
sob medida para o hardware do servidor e registra a tarefa agendada — reduzindo
ao mínimo a intervenção manual e as chances de erro.

> Feito para quem administra servidores no mundo real: leve, direto e à prova de
> ambientes legados.

---

## 🔭 Visão geral

O VigiaBOT roda como uma **tarefa agendada na conta `SYSTEM`**, executando a cada
5 minutos. A cada ciclo ele coleta métricas, compara com limiares configuráveis e
dispara alertas somente quando algo realmente foge do esperado — mantendo
**estado entre execuções** para evitar spam de notificações (CPU sustentada,
cooldown de alertas e detecção de reboot).

A solução é composta por três blocos que trabalham em conjunto:

| Bloco | Papel |
|-------|-------|
| **Agente** (`Monitor.ps1`) | Coleta métricas e envia alertas ao Telegram. |
| **Bot de comandos** (`Monitor-Bot.ps1`) | Responde a comandos de consulta somente leitura (opcional). |
| **Launcher** (`Launcher-Monitoramento.ps1`) | Assistente que instala, configura e parametriza tudo. |

Toda a parametrização é feita por um arquivo externo (`MonitorConfig.json`),
lido e mesclado pelo agente em tempo de execução. Isso permite ajustar o
comportamento **sem editar código**, preservando a integridade do agente.

---

## ✨ Principais funcionalidades

### Monitoramento
- **CPU** com detecção de uso sustentado acima do limiar (evita falsos positivos por picos).
- **Memória RAM** por percentual de uso.
- **Disco** por volume, com limiar independente.
- **Rede**: verificação de conectividade via TCP 443 (não depende de ICMP/ping).
- **Serviços críticos** nomeados e, opcionalmente, todos os serviços automáticos parados.
- **Eventos críticos do sistema**, processos travados, **reinicializações inesperadas** e **BSOD**.
- **Falhas de Backup, Windows Update e Banco de Dados** (SQL Server, MySQL, PostgreSQL, Oracle).

### Alertas
- Notificações **HTML** formatadas no Telegram, com _retry_ e _timeout_ configuráveis.
- **Cooldown** por tipo de alerta para não repetir a mesma notificação em curto intervalo.
- **Log local** com rotação automática.

### Comandos remotos (bot opcional)
- `/status`, `/check`, `/log`, `/servicos`, `/disco`, `/uptime`, `/help` — **somente leitura**.
- Restritos a **Chat IDs autorizados**; instância única para evitar conflito 409.

### Assistente de implantação (Launcher)
- **Implantação Expressa** de ponta a ponta em poucos passos.
- **Validação de token ao vivo** (`getMe`) e **detecção automática do Chat ID** (`getUpdates`), inclusive em grupos.
- **Parametrização inteligente**: inspeciona o hardware e o papel do servidor e sugere limiares e serviços críticos sob medida.
- **Preparo de ambiente** (firewall 443, TLS 1.2, política de execução, teste de conectividade).
- **Painel de status** e **rollback/remoção** assistidos.

---

## 🎯 Objetivos do projeto

- **Simplicidade de implantação**: instalar em um servidor novo deve levar minutos, não horas.
- **Confiabilidade**: alertas relevantes, sem ruído, com estado persistente e cooldown.
- **Zero dependências externas**: apenas Windows + PowerShell nativos.
- **Compatibilidade ampla**: do Windows Server 2012 R2 ao 2022, e Windows 10/11.
- **Segurança por padrão**: segredos fora do código, tarefa isolada, comandos remotos somente leitura.
- **Autonomia do operador**: parametrização sem edição de código, guiada por um assistente.

---

## 📦 Recursos disponíveis

- Agente de monitoramento completo e independente de idioma do SO.
- Bot de comandos de consulta para o Telegram (opcional).
- Assistente interativo de implantação com auto-elevação (UAC).
- Instalador de tarefa agendada com opções de instalar, remover e testar.
- Scripts auxiliares para preparo de ambiente e atualização do agendador.
- Documentação técnica completa: manual, guia de campo, guia de configuração e guia do assistente.
- Definição pronta da tarefa agendada (`.xml`) para importação direta.

---

## 🧰 Requisitos

| Item | Requisito |
|------|-----------|
| **Sistema operacional** | Windows Server 2012 R2, 2016, 2019, 2022 ou Windows 10/11 |
| **PowerShell** | Windows PowerShell **5.1** ou PowerShell **7 (pwsh)** |
| **Privilégios** | Conta de **Administrador** (para instalar a tarefa e o firewall) |
| **Conta de execução** | `SYSTEM` (configurada automaticamente pela tarefa) |
| **Rede** | Saída HTTPS para `api.telegram.org` na **porta 443** |
| **Telegram** | Um **bot** criado no [@BotFather](https://t.me/BotFather) e o **Chat ID** de destino |

> Em Windows Server 2012 R2/2016, o **TLS 1.2** é forçado pelo próprio agente e
> pelo script de preparo de ambiente — requisito para comunicação com o Telegram.

---

## 🚀 Instalação

### Opção recomendada — Assistente (Launcher)

1. **Baixe o repositório** (via `git clone` ou download do ZIP) e mantenha os
   arquivos da pasta [`src/`](src/) **juntos, no mesmo diretório**, no servidor.

   ```bash
   git clone https://github.com/edsilas/VigiaBOT.git
   ```

2. Entre na pasta `src/` e **dê duplo-clique** em **`INICIAR-Assistente.cmd`**.
   Ele se eleva sozinho via UAC e detecta o runtime (`pwsh` ou `powershell.exe`).

3. No menu, escolha **`[1] Implantação Expressa** e siga as instruções. O
   assistente cuida de preparar o ambiente, configurar o Telegram, parametrizar,
   instalar a tarefa e testar o envio.

### Instalação manual (alternativa)

Se preferir não usar o assistente:

```powershell
# Em um PowerShell como Administrador, dentro da pasta src/
.\Install-Monitor.ps1 -Install       # registra a tarefa agendada (SYSTEM)
.\Monitor.ps1 -Test                  # valida token/Chat ID/conectividade e envia teste
```

Para remover:

```powershell
.\Install-Monitor.ps1 -Uninstall
```

---

## ⚙️ Configuração

### Onde ficam os parâmetros

Toda a parametrização vive em **`MonitorConfig.json`**, no diretório de
instalação (por padrão `C:\Monitoramento`). O agente lê esse arquivo em tempo de
execução e o **mescla sobre a configuração padrão** — ou seja, o que estiver no
JSON **prevalece**. Assim, você ajusta o comportamento **sem editar o código**.

> O `MonitorConfig.json` é gerado e mantido pelo Launcher. Ele é ignorado pelo
> Git propositalmente (pode conter o token), conforme o [`.gitignore`](.gitignore).

### Segredos do Telegram

Há duas formas de fornecer o **token** e o **Chat ID**, ambas suportadas pelo Launcher:

| Modo | Como funciona | Quando usar |
|------|---------------|-------------|
| **Arquivo de configuração** (padrão) | Grava `TelegramToken`/`TelegramChatId` no `MonitorConfig.json` (pasta restrita a Administradores). | Mais confiável para a conta `SYSTEM`, sem reiniciar. |
| **Variável de ambiente de máquina** | Define `MONITOR_TG_TOKEN` / `MONITOR_TG_CHATID` no nível da máquina. | Maior isolamento; pode exigir reboot para o `SYSTEM` enxergar. |

### Principais parâmetros

| Parâmetro | Padrão | Descrição |
|-----------|:------:|-----------|
| `CpuThreshold` | `80` | % de CPU que dispara alerta |
| `CpuSustainMinutes` | `5` | Minutos sustentados acima do limiar |
| `RamThreshold` | `80` | % de RAM que dispara alerta |
| `DiskThreshold` | `90` | % de uso por volume |
| `ProcCpuThreshold` | `70` | % de CPU de um único processo |
| `ProcMemThresholdMB` | `2048` | Working set (MB) de um único processo |
| `AlertCooldownMin` | `30` | Intervalo mínimo para repetir o mesmo alerta |
| `CriticalServices` | `@('Spooler')` | Serviços nomeados a vigiar |
| `MonitorAutoStopped` | `true` | Vigiar todos os serviços automáticos parados |
| `DbServicePrefixes` | `MSSQL, MySQL, postgresql, OracleService` | Prefixos de serviços de banco |

Exemplo de `MonitorConfig.json`:

```json
{
  "TelegramToken": "SEU_TOKEN_AQUI",
  "TelegramChatId": "SEU_CHAT_ID_AQUI",
  "CpuThreshold": 85,
  "RamThreshold": 85,
  "DiskThreshold": 90,
  "CriticalServices": ["MSSQLSERVER", "W3SVC", "Spooler"],
  "MonitorAutoStopped": true
}
```

> **Parametrização inteligente**: em vez de preencher isso à mão, use a opção
> **`[3]`** do Launcher — ele inspeciona o servidor e sugere os valores.

---

## 📖 Guia de utilização

### Menu do assistente

Ao executar o Launcher, você verá um menu com as etapas:

| Opção | Ação |
|:-----:|------|
| **1** | **Implantação Expressa** — executa todas as etapas em sequência |
| **2** | Configurar Telegram (token + detecção automática de Chat ID) |
| **3** | Parametrização inteligente (sugestões baseadas no hardware) |
| **4** | Preparar ambiente (firewall 443, TLS 1.2, política de execução) |
| **5** | Instalar/atualizar a tarefa agendada |
| **6** | Instalar/atualizar o bot de comandos (opcional) |
| **7** | Testar agora (envia mensagem de teste) |
| **8** | Painel de status |
| **9** | Remover / Rollback |
| **0** | Sair |

Modo não interativo (expresso direto):

```powershell
.\Launcher-Monitoramento.ps1 -Express
```

### Comandos do bot no Telegram

Depois de instalar o bot (opção `[6]`), envie ao seu bot:

| Comando | Retorna |
|---------|---------|
| `/status` | CPU, RAM, disco e uptime no momento |
| `/check` | Dispara uma ronda completa de monitoramento |
| `/log` | Últimas linhas do log |
| `/servicos` | Estado dos serviços críticos |
| `/disco` | Uso de disco por volume |
| `/uptime` | Tempo ligado / último boot |
| `/help` | Lista de comandos |

> Todos os comandos são **somente leitura** e respondem apenas a Chat IDs
> previamente autorizados.

Documentação detalhada em [`docs/`](docs/):
[manual completo](docs/MANUAL_Monitoramento.md),
[guia de campo](docs/GUIA_CAMPO_Implantacao.txt),
[guia de configuração](docs/LEIAME_Configuracao.txt) e
[guia do assistente](docs/LEIAME_Launcher.md).

---

## 🗂️ Estrutura do projeto

```
VigiaBOT/
├── README.md                       # Este documento
├── LICENSE                         # Apache License 2.0
├── CHANGELOG.md                    # Histórico de versões
├── CONTRIBUTING.md                 # Guia de contribuição
├── .gitignore                      # Arquivos ignorados (segredos, logs, estado)
│
├── src/                            # Pacote de implantação (mantenha os arquivos juntos)
│   ├── INICIAR-Assistente.cmd      # Bootstrapper de duplo-clique (auto-elevação UAC)
│   ├── Launcher-Monitoramento.ps1  # Assistente interativo de implantação
│   ├── Monitor.ps1                 # Agente de monitoramento (núcleo)
│   ├── Monitor-Bot.ps1             # Listener de comandos do Telegram (opcional)
│   ├── Install-Monitor.ps1         # Instalador da tarefa agendada
│   ├── MonitoramentoServidor.xml   # Definição da tarefa agendada
│   ├── Preparar-Ambiente.cmd       # Firewall 443, TLS 1.2, política de execução
│   ├── Atualizar-Agendador.cmd     # Reregistra as tarefas
│   └── Agendar-Bot.cmd             # Agenda o bot de comandos (ONSTART)
│
└── docs/                           # Documentação técnica
    ├── MANUAL_Monitoramento.md     # Manual completo
    ├── GUIA_CAMPO_Implantacao.txt  # Passo a passo de campo
    ├── LEIAME_Configuracao.txt     # Guia de configuração
    └── LEIAME_Launcher.md          # Guia do assistente
```

> Os arquivos de `src/` são projetados para **coexistir no mesmo diretório** —
> o Launcher os copia para o diretório de instalação e o bootstrapper localiza o
> assistente por caminho relativo. Não os separe em subpastas.

---

## 🏛️ Arquitetura da solução

```
        +-------------------+          duplo-clique / UAC
        | INICIAR-Assistente| ---------------------------------+
        +-------------------+                                  |
                                                               v
                                            +--------------------------------+
                                            |  Launcher-Monitoramento.ps1    |
                                            |  (assistente de implantação)   |
                                            +--------------------------------+
                                              |        |          |        |
              grava/mescla                    |        |          |        | reutiliza
        +----------------------+  <-----------+        |          |        +----------------------+
        |  MonitorConfig.json  |  (override)           |          |        | Install-Monitor.ps1  |
        +----------------------+                       |          |        +----------------------+
                 ^                                      |          |                    |
                 | lê e mescla sobre padrão             | valida   | detecta            | registra
                 |                                      | token    | Chat ID            v
        +----------------------+   alertas HTTPS 443   (getMe)   (getUpdates)   +------------------------+
        |     Monitor.ps1      | --------------------------------------------->  |  Agendador (SYSTEM)    |
        |  (agente / 5 min)    |            api.telegram.org                     |  tarefa a cada 5 min   |
        +----------------------+                                                +------------------------+
                 |  estado                                    ^  comandos (opcional)
                 v                                            |
        +----------------------+                     +----------------------+
        |   MonitorState.json  |                     |    Monitor-Bot.ps1   |
        |  (CPU/cooldown/boot) |                     | long-poll getUpdates |
        +----------------------+                     +----------------------+
```

**Princípio central de design:** o agente lê um **override externo**
(`MonitorConfig.json`) e o mescla sobre sua configuração padrão. Toda a
parametrização passa por esse arquivo — por isso o Launcher nunca precisa
alterar `Monitor.ps1`. Isso garante **compatibilidade total** e atualizações
seguras do agente.

Características arquiteturais:

- **Execução isolada** como `SYSTEM`, via Agendador de Tarefas (gatilhos de tempo e de boot, reinício em falha).
- **Estado persistente** em `MonitorState.json` para decisões entre ciclos (CPU sustentada, cooldown, detecção de reboot).
- **Locale-safe**: uso de contadores CIM/WMI, independentes do idioma do SO.
- **Conectividade resiliente**: pré-checagem por TCP 443 e TLS 1.2 forçado.
- **Instância única** do bot via mutex, evitando o conflito 409 do `getUpdates`.

---

## 🛠️ Tecnologias utilizadas

- **PowerShell** (Windows PowerShell 5.1 e PowerShell 7) — linguagem do agente, do bot e do assistente.
- **Windows Scripting (`.cmd`/Batch)** — bootstrapper de duplo-clique e scripts de preparo.
- **Agendador de Tarefas do Windows** (`schtasks` / `Register-ScheduledTask`) — execução automática como `SYSTEM`.
- **CIM/WMI** — coleta de métricas independente de idioma.
- **API HTTP do Telegram Bot** (`getMe`, `getUpdates`, `sendMessage`) — validação, detecção de Chat ID e envio de alertas.
- **JSON** — configuração externa (`MonitorConfig.json`) e estado (`MonitorState.json`).
- **XML** — definição da tarefa agendada.

---

## ✅ Boas práticas

O projeto foi construído seguindo princípios que facilitam manutenção e operação:

- **Segredos fora do código**: token e Chat ID vêm de variável de ambiente ou do `MonitorConfig.json`, nunca versionados.
- **Compatibilidade retroativa**: código do agente sem construções exclusivas do PS7 (sem operador ternário, `??` ou `?.`).
- **ASCII nos scripts** `.ps1`/`.cmd` para evitar mojibake em consoles legados; acentuação apenas na documentação.
- **Sem dependências externas** no agente — apenas recursos nativos do Windows.
- **Idempotência**: reinstalar/atualizar a tarefa não duplica agendamentos.
- **Operações reversíveis**: o Launcher faz backup (`.bak`) antes de editar arquivos e oferece rollback.
- **Menor privilégio nos comandos remotos**: o bot é estritamente somente leitura e restrito a Chat IDs autorizados.
- **Configuração por override**, mantendo o núcleo do agente intocado.

---

## 🗺️ Roadmap

Ideias e melhorias planejadas para versões futuras (sujeitas a evolução):

- [ ] Empacotamento em **release** com verificação de integridade (checksums).
- [ ] Suporte a **múltiplos destinos** de alerta (vários Chat IDs / canais).
- [ ] **Perfis de parametrização** exportáveis/importáveis entre servidores.
- [ ] Integração opcional com **e-mail (SMTP)** como canal alternativo de alerta.
- [ ] Painel de status consolidado para **frotas** de servidores.
- [ ] **Templates de issue e Pull Request** e um `CODE_OF_CONDUCT.md`.
- [ ] Testes automatizados com **Pester** e verificação de estilo com **PSScriptAnalyzer**.
- [ ] Internacionalização das mensagens de alerta.

Sugestões são bem-vindas via [issues](https://github.com/edsilas/VigiaBOT/issues).

---

## 🤝 Contribuição

Contribuições são bem-vindas! Consulte o guia completo em
[**CONTRIBUTING.md**](CONTRIBUTING.md). Em resumo:

1. Abra uma **issue** descrevendo o bug ou a proposta.
2. Faça um **fork** e crie um branch (`feat/...`, `fix/...`, `docs/...`).
3. Mantenha os padrões: **PowerShell 5.1 + 7**, **ASCII** nos scripts, **sem segredos** no commit.
4. Valide em **homologação** e abra um **Pull Request** claro, referenciando a issue.

Ao contribuir, você concorda que sua contribuição será licenciada sob a
**Apache License 2.0**.

---

## 📝 Changelog

### Versão 1.0.1 — 2026-07-08

- **Corrigido**: o robô de comandos do Telegram (`Monitor-Bot.ps1`) não
  respondia quando os segredos eram definidos pelo modo padrão do assistente
  ("Arquivo de configuração"). O bot agora lê o mesmo `MonitorConfig.json` do
  agente (token, Chat IDs autorizados por união, serviços críticos e tarefa),
  resolve o caminho do `/log` de forma robusta e entrega respostas em texto
  simples caso o envio em HTML falhe. Sem regressões.

### Versão 1.0.0 — 2026-07-04

Primeira versão pública do **VigiaBOT**.

- **Adicionado**: agente de monitoramento (`Monitor.ps1`), bot de comandos
  (`Monitor-Bot.ps1`), instalador de tarefa (`Install-Monitor.ps1`) e o
  **assistente interativo de implantação** (`Launcher-Monitoramento.ps1`) com
  Implantação Expressa, validação de token ao vivo, detecção automática de Chat
  ID, parametrização inteligente, preparo de ambiente, painel de status e
  rollback.
- **Adicionado**: bootstrapper de duplo-clique com auto-elevação (UAC), scripts
  auxiliares e documentação técnica completa.
- **Segurança**: remoção de credenciais reais embutidas no código (substituídas
  por marcadores) e `.gitignore` protegendo segredos, logs e estado.
- **Compatibilidade**: Windows Server 2012 R2/2016/2019/2022 e Windows 10/11;
  Windows PowerShell 5.1 e PowerShell 7.

O histórico completo está em [**CHANGELOG.md**](CHANGELOG.md).

---

## 📄 Licença

Distribuído sob a **Apache License 2.0**. Consulte o arquivo [**LICENSE**](LICENSE)
para o texto completo.

```
Copyright © 2026 Edsilas

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0
```

---

## 👤 Créditos

**Desenvolvido por Edsilas**

Se este projeto foi útil para você, considere deixar uma ⭐ no repositório.

<div align="center">

**VigiaBOT** — vigiando seus servidores para que você não precise. 🛡️

</div>
