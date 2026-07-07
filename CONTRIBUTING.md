# Contribuindo com o VigiaBOT

Obrigado pelo interesse em contribuir! Este documento reúne as diretrizes para
propor melhorias, corrigir problemas e manter a qualidade do projeto.

## Como contribuir

1. **Abra uma issue** descrevendo o bug ou a proposta de melhoria antes de
   iniciar mudanças maiores. Isso evita trabalho duplicado e alinha expectativas.
2. **Faça um fork** do repositório e crie um branch a partir de `main`:
   - `feat/nome-da-funcionalidade` para novas funcionalidades;
   - `fix/descricao-curta` para correções;
   - `docs/descricao-curta` para documentação.
3. **Implemente** a mudança respeitando os padrões descritos abaixo.
4. **Abra um Pull Request** com uma descrição clara do que mudou e por quê,
   referenciando a issue correspondente.

## Padrões de código

- **PowerShell**: manter compatibilidade com **Windows PowerShell 5.1** e
  **PowerShell 7**. Evitar construções exclusivas do PS7 (operador ternário,
  `??`, `?.`) nos scripts que rodam como agente.
- **ASCII apenas** nos arquivos `.ps1` e `.cmd`, para evitar problemas de
  codificação (mojibake) em consoles legados de Windows Server. Acentuação é
  permitida apenas na documentação (`.md`).
- **Sem dependências externas** no agente (`Monitor.ps1`): usar apenas recursos
  nativos do Windows/PowerShell.
- **Locale-safe**: preferir contadores CIM/WMI a strings dependentes de idioma.
- Preservar o mecanismo de **override por `MonitorConfig.json`**: novos
  parâmetros devem poder ser configurados por esse arquivo, sem exigir edição
  do código do agente.

## Segurança

- **Nunca** faça commit de tokens, Chat IDs reais ou qualquer segredo.
- O arquivo `MonitorConfig.json` é ignorado pelo Git propositalmente; não o
  force para dentro do repositório.
- Ao reportar uma vulnerabilidade, prefira contato privado com o mantenedor a
  abrir uma issue pública.

## Testes

- Sempre que possível, valide as mudanças em um **servidor de homologação**
  antes de propor o merge, cobrindo Windows PowerShell 5.1 e PowerShell 7.
- Descreva no Pull Request o ambiente utilizado nos testes (versão do Windows
  Server e do PowerShell).

## Documentação

- Atualize o `README.md`, os guias em `docs/` e o `CHANGELOG.md` sempre que a
  mudança afetar comportamento, configuração ou instalação.

## Licença das contribuições

Ao contribuir, você concorda que sua contribuição será licenciada sob a
**Apache License 2.0**, a mesma do projeto.
