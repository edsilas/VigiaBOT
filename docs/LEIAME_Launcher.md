# 🚀 Assistente de Implantação — Monitoramento de Servidor Windows

Um **launcher inteligente** que automatiza toda a implantação do monitoramento
(alertas via Telegram), guiando o operador passo a passo, validando tudo ao vivo
e **sugerindo a melhor parametrização com base no próprio servidor**.

> Construído sobre a implementação já existente, **sem alterar** `Monitor.ps1`,
> `Install-Monitor.ps1` ou o XML da tarefa. Toda a parametrização é gravada em
> `C:\Monitoramento\MonitorConfig.json` — o override externo que o `Monitor.ps1`
> **já sabe ler e mesclar** sobre a configuração padrão.

---

## 📦 Arquivos deste pacote

| Arquivo | Função |
|---|---|
| `INICIAR-Assistente.cmd` | Atalho de **duplo-clique**. Pede admin (UAC) e abre o assistente. |
| `Launcher-Monitoramento.ps1` | O assistente em si (menu interativo + modo expresso). |
| `LEIAME_Launcher.md` | Este guia. |

Coloque estes 3 arquivos na **mesma pasta** dos arquivos originais
(`Monitor.ps1`, `MonitoramentoServidor.xml`, `Install-Monitor.ps1` e, opcionalmente,
`Monitor-Bot.ps1`). O assistente copia tudo para `C:\Monitoramento` sozinho.

---

## ▶️ Como usar (o jeito mais simples)

1. Dê **duplo-clique** em `INICIAR-Assistente.cmd`.
2. Aceite o pedido de Administrador (UAC).
3. Escolha **[1] Implantação Expressa** e siga as perguntas.

Em poucos minutos o servidor estará vigiado e avisando no Telegram.

> Alternativa por linha de comando (PowerShell como Administrador):
> ```powershell
> powershell -ExecutionPolicy Bypass -File .\Launcher-Monitoramento.ps1 -Express
> ```

---

## 🧭 Menu do assistente

| Opção | O que faz |
|---|---|
| **1. Implantação Expressa** | Faz tudo do zero, guiado: ambiente → Telegram → parâmetros → tarefa → (bot) → teste. |
| **2. Configurar Telegram** | Valida o token ao vivo (mostra `@seu_bot`) e **detecta o Chat ID automaticamente** lendo a mensagem que você enviar ao bot. |
| **3. Parametrização inteligente** | Analisa o servidor e sugere limiares e serviços críticos. |
| **4. Preparar ambiente** | Firewall de saída 443, TLS 1.2 forte, ExecutionPolicy e teste de conectividade. |
| **5. Instalar/atualizar tarefa** | Registra a tarefa (5 min, SYSTEM) reaproveitando o `Install-Monitor.ps1`. |
| **6. Instalar/atualizar bot** | (Opcional) Bot de comandos `/status`, `/log`, `/disco`… iniciando no boot. |
| **7. Testar agora** | Diagnóstico + mensagem de teste no Telegram. |
| **8. Painel de status** | Estado das tarefas, credenciais (mascaradas), **config efetiva** e últimas linhas do log. |
| **9. Remover / Rollback** | Remove tarefas, regras de firewall e (opcional) as variáveis. |

---

## 🔎 Detecção automática do Chat ID

Nada de abrir `@userinfobot` nem colar números à mão. O assistente:

1. Confere o token com o Telegram (`getMe`) e exibe o nome do bot.
2. Pede que você **envie uma mensagem ao bot** (ou ao grupo, se adicionar o bot lá).
3. **Lê essa mensagem** e mostra o Chat ID já pronto (funciona para conversa
   privada **e** grupo/supergrupo).

Se o bot de comandos estiver rodando, ele é pausado durante a leitura (para evitar
o conflito 409 do Telegram) e reativado logo em seguida — automaticamente.

---

## 🧠 Parametrização inteligente (o que ele sugere e por quê)

O assistente inspeciona o servidor e propõe valores sob medida:

- **Serviços críticos**: detecta SQL Server (inclusive instâncias `MSSQL$NOME`),
  MySQL, PostgreSQL, Oracle e IIS (`W3SVC`) e já os adiciona à vigilância.
  `Spooler` só entra se estiver como automático (evita ruído em servidores).
- **Memória por processo** (`ProcMemThresholdMB`): escala com a RAM total
  (2 GB padrão; 4 GB em servidores ≥ 32 GB; 8 GB em ≥ 64 GB) para não gerar
  alarme com processos que usam bastante memória por projeto.
- **RAM** (`RamThreshold`): 85% em servidores pequenos (≤ 4 GB), 80% no restante.
- **Serviços automáticos parados** (`MonitorAutoStopped`): ligado em servidores,
  desligado em estações (onde há muitos serviços *trigger-start* que só fazem ruído).
- Alerta sobre **VMs** (risco de falso `REDE_DOWN` quando só há placas virtuais).

Você vê uma tabela **Sugerido × Padrão** e pode aceitar tudo (Enter) ou ajustar
item a item. O resultado vai para `MonitorConfig.json`; **a próxima ronda (até 5
min) já usa** — sem reinstalar.

---

## 🔐 Onde ficam o Token e o Chat ID

Ao configurar o Telegram, você escolhe:

- **[1] Arquivo de config** (`MonitorConfig.json`, recomendado para implantação
  rápida): a tarefa `SYSTEM` lê direto do arquivo, **sem precisar reiniciar** o
  servidor. O arquivo fica em `C:\Monitoramento` (pasta acessível só a
  Administradores).
- **[2] Variável de máquina**: mantém as credenciais fora do arquivo. Pode exigir
  **reiniciar o servidor** para a tarefa `SYSTEM` enxergar os novos valores.

Em ambos os casos o assistente respeita a ordem de precedência que o `Monitor.ps1`
já implementa e valida o envio na hora.

---

## ✅ Compatibilidade

- **Windows PowerShell 5.1** (ideal) e **PowerShell 7**; degrada com segurança em
  ambientes legados. Código sem acentos para não corromper consoles antigos
  (Server 2012 R2/2016).
- **Não modifica** os scripts originais. A única edição opcional é no
  `Monitor-Bot.ps1` (para autorizar seu Chat ID nos comandos), sempre **com backup
  `.bak`** e mediante confirmação.
- Reaproveita `Install-Monitor.ps1` para registrar a tarefa; se ele não estiver
  presente, cai para registro por XML ou `schtasks` — sem perder funcionalidade.

---

## 🆘 Diagnóstico rápido

| Sintoma | Ação |
|---|---|
| "Admin: NAO" no topo | Feche e use o `INICIAR-Assistente.cmd` (ele eleva sozinho). |
| "Telegram(443): FALHOU" | Opção **4** (Preparar ambiente) e libere `api.telegram.org:443` na borda/proxy. |
| Token rejeitado | Recopie o token inteiro do `@BotFather` (com os dois-pontos no meio). |
| Não detecta Chat ID | Toque em **Iniciar** no bot e envie uma mensagem; ou informe manualmente. |
| Tarefa não envia (modo variável) | Reinicie o servidor **ou** reconfigure escolhendo a opção "Arquivo de config". |

Detalhes completos continuam no `GUIA_CAMPO_Implantacao.txt`, `LEIAME_Configuracao.txt`
e `MANUAL_Monitoramento.md`.
