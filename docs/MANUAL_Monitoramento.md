# 📊 Monitoramento de Servidor Windows com Alertas no Telegram
### Manual de Uso e Configuração — versão para iniciantes

> Este guia foi escrito para qualquer pessoa, mesmo sem experiência técnica.
> Siga os passos na ordem e, ao final, você terá um "vigia" automático no seu
> servidor Windows que avisa no seu celular sempre que algo der errado.

---

## 📑 Índice

1. [O que é esta ferramenta?](#1-o-que-é-esta-ferramenta)
2. [O que ela vigia (funcionalidades)](#2-o-que-ela-vigia-funcionalidades)
3. [Quais avisos/relatórios ela entrega](#3-quais-avisosrelatórios-ela-entrega)
4. [Antes de começar (pré-requisitos)](#4-antes-de-começar-pré-requisitos)
5. [Passo 1 — Criar o robô (bot) do Telegram](#5-passo-1--criar-o-robô-bot-do-telegram)
6. [Passo 2 — Descobrir o seu Chat ID](#6-passo-2--descobrir-o-seu-chat-id)
7. [Passo 3 — Instalar a ferramenta no servidor](#7-passo-3--instalar-a-ferramenta-no-servidor)
8. [Passo 4 — Guardar o Token e o Chat ID](#8-passo-4--guardar-o-token-e-o-chat-id)
9. [Passo 5 — Testar se está funcionando](#9-passo-5--testar-se-está-funcionando)
10. [Configurações que você pode ajustar](#10-configurações-que-você-pode-ajustar)
11. [Onde ficam os registros (logs)](#11-onde-ficam-os-registros-logs)
12. [Como remover a ferramenta](#12-como-remover-a-ferramenta)
13. [Problemas comuns e soluções](#13-problemas-comuns-e-soluções)
14. [Glossário (palavras difíceis explicadas)](#14-glossário-palavras-difíceis-explicadas)

---

## 1. O que é esta ferramenta?

Imagine um **vigia que nunca dorme**. A cada **5 minutos**, ele faz uma "ronda"
no seu servidor Windows, checa se está tudo bem (memória, disco, programas,
serviços, etc.) e, **se encontrar algum problema, manda uma mensagem direto no
seu Telegram**, no seu celular ou computador.

Você **não precisa ficar olhando** o servidor o tempo todo. A ferramenta avisa
sozinha. Se ela ficar quieta, é porque está tudo certo.

A ferramenta é composta por 3 arquivos:

| Arquivo | Para que serve |
|---|---|
| `Monitor.ps1` | O "cérebro" — é ele que faz a vigilância e envia os avisos. |
| `MonitoramentoServidor.xml` | A "agenda" — diz ao Windows para rodar o vigia a cada 5 minutos. |
| `Install-Monitor.ps1` | O "instalador" — coloca tudo no lugar com um comando só. |

---

## 2. O que ela vigia (funcionalidades)

A ferramenta verifica automaticamente, a cada 5 minutos:

| O que é checado | Quando dispara um aviso |
|---|---|
| 🔥 **CPU (processador)** | Acima de **80%** por mais de **5 minutos seguidos** |
| 🧠 **Memória RAM** | Acima de **80%** de uso |
| 💾 **Disco** | Acima de **90%** cheio (em qualquer unidade: C:, D:, etc.) |
| 🌐 **Rede** | Quando nenhum cabo/placa de rede está conectado |
| ⚙️ **Serviços do Windows** | Quando um serviço importante está **parado** |
| ⚠️ **Erros graves do sistema** | Erros críticos registrados no Windows |
| 🪟 **Programas travados** | Aplicações que pararam de responder |
| 🔄 **Reinicializações inesperadas** | Quando o servidor reinicia sozinho |
| 💙 **Tela azul (BSOD)** | Quando ocorre uma tela azul de erro |
| 📦 **Falha de Backup** | Quando uma cópia de segurança falha |
| 🔧 **Falha do Windows Update** | Quando uma atualização não conclui |
| 🗄️ **Falha de Banco de Dados** | Quando o serviço de banco (SQL, MySQL, etc.) cai |
| 📈 **Processo "comendo" CPU** | Um único programa usando muita CPU |
| 📊 **Processo "comendo" memória** | Um único programa usando muita memória |

**Recursos inteligentes embutidos:**

- ✅ **Reenvio automático**: se a internet falhar na hora de avisar, ele tenta de novo (3 vezes).
- ✅ **Não enche o saco**: não repete o mesmo aviso antes de 30 minutos.
- ✅ **Não inventa alarme falso**: só avisa de CPU alta se ela ficar alta de verdade por 5 minutos.
- ✅ **Guarda um histórico** (registro/log) no próprio servidor, com limpeza automática.
- ✅ **Funciona mesmo sem ninguém logado** no servidor.
- ✅ **À prova de falhas**: se uma verificação der erro, as outras continuam funcionando.

---

## 3. Quais avisos/relatórios ela entrega

A ferramenta **não gera um relatório em PDF/planilha**. Ela entrega **avisos em
tempo real no Telegram** e mantém um **histórico em arquivo de texto** no servidor.

### 3.1. Aviso no Telegram (o principal)

Sempre que algo dá errado, chega uma mensagem assim no seu Telegram:

```
🔴 ALERTA DE MONITORAMENTO
Servidor: SRV-FINANCEIRO
Data/Hora: 18/06/2026 14:35:10
Ocorrências: 2

[CRÍTICO] DISCO_CHEIO
Processo/Alvo: C:
Valor: 93% usado (4.1 GB livres)
Recomendação: Libere espaço (logs, temp, dumps), expanda o volume ou mova dados.

[ALTO] RAM_ALTA
Processo/Alvo: Memória
Valor: 86%
Recomendação: Verifique vazamento de memória, ajuste cache da aplicação ou amplie a RAM.
```

Cada item do aviso sempre traz:

- 🖥️ **Nome do servidor** afetado
- 🕒 **Data e hora** exata
- 🎯 **O que está com problema** (disco, processo, serviço...)
- 📏 **O valor detectado** (ex.: "93% usado")
- 🚦 **Nível de gravidade**: Crítico, Alto, Médio ou Baixo
- 💡 **Recomendação técnica** do que fazer

### 3.2. Mensagem de teste

Quando você roda o teste (Passo 5), chega uma mensagem simples confirmando que
a comunicação com o Telegram está funcionando.

### 3.3. Aviso de falha do próprio vigia

Se a ferramenta tiver um problema grave nela mesma, ela tenta avisar com a
mensagem **"FALHA NO MONITORAMENTO"** — assim você sabe que o vigia precisa de atenção.

### 3.4. Histórico no servidor (log)

No servidor fica um arquivo de texto com tudo que aconteceu (ronda iniciada,
valores medidos, avisos enviados). Veja a [seção 11](#11-onde-ficam-os-registros-logs).

---

## 4. Antes de começar (pré-requisitos)

Você vai precisar de:

- ☑️ Um servidor com **Windows** (Server 2012 R2, 2016, 2019, 2022 — ou Windows 10/11).
- ☑️ **Permissão de Administrador** no servidor.
- ☑️ O aplicativo **Telegram** instalado no seu celular ou computador.
- ☑️ Os 3 arquivos da ferramenta (`Monitor.ps1`, `MonitoramentoServidor.xml`, `Install-Monitor.ps1`).
- ☑️ Cerca de **15 minutos** para a configuração inicial.

> 💡 Não é preciso instalar nenhum programa extra. A ferramenta usa só recursos
> que já vêm no Windows.

---

## 5. Passo 1 — Criar o robô (bot) do Telegram

O "bot" é o robozinho que vai enviar as mensagens para você. É grátis e leva 2 minutos.

1. Abra o **Telegram** e, na busca, procure por: **@BotFather** (com o selo azul de verificado).
2. Abra a conversa com o BotFather e toque/clique em **Iniciar** (ou digite `/start`).
3. Envie a mensagem: `/newbot`
4. Ele vai pedir um **nome** para o bot. Digite algo como: `Vigia do Servidor`
5. Depois vai pedir um **usuário** (precisa terminar em `bot`). Ex.: `vigia_srv_financeiro_bot`
6. Pronto! O BotFather vai responder com uma mensagem contendo o **Token**.
   É um código grande parecido com isto:

   ```
   123456789:AAExEmpLo-DeToKeN_naoUseEsteAqui12345
   ```

7. **Copie e guarde esse Token** num lugar seguro. Você vai usá-lo no Passo 4.

> ⚠️ **O Token é como a senha do bot.** Nunca compartilhe publicamente.

---

## 6. Passo 2 — Descobrir o seu Chat ID

O **Chat ID** é o "endereço" para onde as mensagens serão enviadas (você ou um grupo).

**Para receber as mensagens em particular (no seu próprio Telegram):**

1. Procure o seu bot recém-criado pelo usuário (ex.: `@vigia_srv_financeiro_bot`) e abra a conversa.
2. Toque em **Iniciar** e envie qualquer mensagem, por exemplo: `oi`
3. Agora, na busca do Telegram, procure por: **@userinfobot** e abra a conversa.
4. Toque em **Iniciar**. Ele vai responder com o seu **Id** — um número como `987654321`.
5. **Esse número é o seu Chat ID.** Guarde-o para o Passo 4.

**Se você quiser que os avisos cheguem em um GRUPO** (recomendado para equipes):

1. Crie um grupo no Telegram e **adicione o seu bot** como membro.
2. Adicione também o **@userinfobot** ao grupo (ou use o bot `@RawDataBot`).
3. O Chat ID de grupo costuma ser um número **negativo**, ex.: `-1001234567890`.
4. Use esse número como Chat ID. Depois você pode remover o @userinfobot do grupo.

---

## 7. Passo 3 — Instalar a ferramenta no servidor

1. No servidor, crie a pasta `C:\Monitoramento` (se ainda não existir).
2. Copie os 3 arquivos para dentro dela:
   - `C:\Monitoramento\Monitor.ps1`
   - `C:\Monitoramento\MonitoramentoServidor.xml`
   - `C:\Monitoramento\Install-Monitor.ps1`
3. Abra o **PowerShell como Administrador**:
   - Clique no menu Iniciar, digite `PowerShell`.
   - Clique com o botão direito em **Windows PowerShell** e escolha **Executar como administrador**.
4. Dentro do PowerShell, vá até a pasta e rode o instalador:

   ```powershell
   cd C:\Monitoramento
   .\Install-Monitor.ps1 -Install
   ```

5. Se aparecer a mensagem **"Tarefa registrada"**, deu certo! O Windows já vai
   rodar a vigilância sozinho a cada 5 minutos.

> 💡 O instalador cria automaticamente a "Tarefa Agendada" que faz o vigia rodar
> a cada 5 minutos, mesmo sem ninguém logado, e reinicia em caso de falha.

---

## 8. Passo 4 — Guardar o Token e o Chat ID

Você tem **duas opções**. A primeira é a mais segura.

### Opção A — Variáveis de ambiente (recomendada, mais segura)

No PowerShell **como Administrador**, rode (trocando pelos seus valores):

```powershell
[Environment]::SetEnvironmentVariable('MONITOR_TG_TOKEN','SEU_TOKEN_AQUI','Machine')
[Environment]::SetEnvironmentVariable('MONITOR_TG_CHATID','SEU_CHATID_AQUI','Machine')
```

Exemplo preenchido:

```powershell
[Environment]::SetEnvironmentVariable('MONITOR_TG_TOKEN','123456789:AAExEmpLo-DeToKeN12345','Machine')
[Environment]::SetEnvironmentVariable('MONITOR_TG_CHATID','987654321','Machine')
```

> Vantagem: o Token não fica escrito dentro do arquivo do programa.

### Opção B — Escrever direto no arquivo (mais simples)

1. Abra o arquivo `C:\Monitoramento\Monitor.ps1` no **Bloco de Notas**.
2. Logo no começo, procure por estas linhas:

   ```
   TelegramToken  = ... 'SUBSTITUA_PELO_SEU_TOKEN_DO_BOTFATHER'
   TelegramChatId = ... 'SUBSTITUA_PELO_SEU_CHAT_ID'
   ```
3. Troque os textos `SUBSTITUA...` pelo seu Token e Chat ID reais (mantendo as aspas).
4. Salve o arquivo.

---

## 9. Passo 5 — Testar se está funcionando

No PowerShell **como Administrador**, dentro da pasta, rode:

```powershell
cd C:\Monitoramento
.\Install-Monitor.ps1 -Test
```

O que deve acontecer:

- Na tela, você verá um diagnóstico (Internet: OK, Config Telegram: VÁLIDA).
- No seu **Telegram**, deve chegar uma mensagem de **teste**.

✅ **Chegou a mensagem?** Está tudo pronto! A partir de agora a ferramenta vigia sozinha.

❌ **Não chegou?** Veja a [seção 13 — Problemas comuns](#13-problemas-comuns-e-soluções).

> Para forçar uma ronda completa imediatamente (sem esperar os 5 minutos):
> ```cmd
> schtasks /Run /TN "MonitoramentoServidor"
> ```

---

## 10. Configurações que você pode ajustar

Tudo fica no começo do arquivo `Monitor.ps1`, num bloco fácil de editar.
Abra no Bloco de Notas e ajuste o que precisar:

| Configuração | O que faz | Valor padrão |
|---|---|---|
| `CpuThreshold` | % de CPU que dispara aviso | `80` |
| `CpuSustainMinutes` | Por quantos minutos a CPU precisa ficar alta | `5` |
| `RamThreshold` | % de memória que dispara aviso | `80` |
| `DiskThreshold` | % de disco cheio que dispara aviso | `90` |
| `ProcCpuThreshold` | % de CPU de um único programa | `70` |
| `ProcMemThresholdMB` | Memória (MB) de um único programa | `2048` |
| `AlertCooldownMin` | Minutos antes de repetir o mesmo aviso | `30` |
| `CriticalServices` | Lista de serviços que você considera importantes | `'Spooler'` |
| `DbServicePrefixes` | Tipos de banco de dados a vigiar | `'MSSQL','MySQL',...` |
| `LogMaxBytes` | Tamanho máximo do arquivo de log | `5MB` |
| `LogKeepFiles` | Quantos logs antigos guardar | `7` |

**Exemplo — vigiar serviços de um servidor com SQL Server e site IIS:**

```
CriticalServices = @('MSSQLSERVER', 'W3SVC', 'Spooler')
```

> 💡 Depois de editar o arquivo, **não precisa reinstalar** — a próxima ronda
> (em até 5 minutos) já usa as novas configurações.

---

## 11. Onde ficam os registros (logs)

O histórico fica na pasta:

```
C:\Monitoramento\logs\monitor.log
```

Abra com o Bloco de Notas para ver tudo que aconteceu. Exemplo:

```
[2026-06-18 14:35:09] [INFO] === Início do ciclo ===
[2026-06-18 14:35:10] [INFO] CPU total: 23%
[2026-06-18 14:35:11] [INFO] RAM: 41%
[2026-06-18 14:35:12] [CRITICAL] ALERTA [Crítico] DISCO_CHEIO | C: | 93% usado
[2026-06-18 14:35:14] [INFO] Alerta enviado ao Telegram (1 ocorrências).
[2026-06-18 14:35:14] [INFO] === Fim do ciclo (duração 5.2s) ===
```

> O log se "limpa" sozinho: quando passa de 5 MB, ele arquiva e mantém só os 7 mais recentes.

---

## 12. Como remover a ferramenta

No PowerShell **como Administrador**:

```powershell
cd C:\Monitoramento
.\Install-Monitor.ps1 -Uninstall
```

Isso remove a tarefa agendada (o vigia para de rodar). Se quiser, depois você pode
apagar a pasta `C:\Monitoramento` manualmente.

> Para remover usando só comando do Windows:
> ```cmd
> schtasks /Delete /TN "MonitoramentoServidor" /F
> ```

---

## 13. Problemas comuns e soluções

| Problema | Provável causa | Solução |
|---|---|---|
| Não chega mensagem no Telegram | Token ou Chat ID errado | Refaça os Passos 1, 2 e 4 com atenção |
| "Config Telegram: INVÁLIDA" no teste | Token no formato errado ou ainda com "SUBSTITUA" | Confira se copiou o Token completo |
| "Internet: FALHOU" no teste | Servidor sem internet / firewall bloqueando | Libere o acesso a `api.telegram.org` |
| Mensagem só chega quando você manda algo ao bot | Você não iniciou conversa com o bot | Abra o bot e toque em **Iniciar** |
| Aparece erro de "execução de scripts desativada" | Política de segurança do Windows | A tarefa já usa `-ExecutionPolicy Bypass`; para testes manuais, adicione esse parâmetro |
| Não consigo rodar o instalador | PowerShell sem privilégio de admin | Abra o PowerShell com **Executar como administrador** |
| Recebo avisos demais | Limiares baixos demais para o seu ambiente | Ajuste os valores na [seção 10](#10-configurações-que-você-pode-ajustar) |
| Avisa serviço parado que eu não uso | Serviço automático que não importa | Não precisa fazer nada, ou ajuste a lista de serviços |

**Como ver se a tarefa está ativa:**

1. Menu Iniciar → digite **Agendador de Tarefas** → abra.
2. Procure por **MonitoramentoServidor** na lista.
3. Veja a coluna **Status** (deve estar "Pronto") e a hora da "Última Execução".

---

## 14. Glossário (palavras difíceis explicadas)

| Palavra | Significado simples |
|---|---|
| **CPU** | O "cérebro" do computador, que faz as contas. |
| **RAM / Memória** | A "mesa de trabalho" onde os programas ficam abertos. |
| **Serviço** | Programa que roda escondido no fundo do Windows (ex.: impressão, banco de dados). |
| **Log** | Arquivo de histórico/diário do que aconteceu. |
| **Bot** | Robozinho automático do Telegram que envia as mensagens. |
| **Token** | A "senha" do bot, que permite enviar mensagens. |
| **Chat ID** | O "endereço" de quem vai receber as mensagens. |
| **BSOD** | "Tela azul da morte" — erro grave que reinicia o Windows. |
| **Backup** | Cópia de segurança dos seus dados. |
| **Tarefa Agendada** | Recurso do Windows que roda um programa em horários definidos. |
| **PowerShell** | Programa do Windows usado para rodar comandos e scripts. |
| **Administrador** | Usuário com permissão total no computador. |

---

### ✅ Resumindo em uma frase

Crie o bot → pegue o Token e o Chat ID → instale com `Install-Monitor.ps1 -Install`
→ guarde o Token/Chat ID → teste com `-Test`. Pronto: seu servidor agora avisa
sozinho no Telegram quando algo dá errado.

---

*Documento de apoio à ferramenta de Monitoramento de Servidor Windows.*
*Em caso de dúvida técnica, consulte a equipe de TI/Infraestrutura.*
