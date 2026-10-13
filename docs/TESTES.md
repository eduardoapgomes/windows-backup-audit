# Testes

## Automáticos (a cada envio ao GitHub)

O workflow [Windows tests](https://github.com/eduardoapgomes/windows-backup-audit/actions/workflows/tests.yml) roda no Windows Server mais recente, **duas vezes**: no Windows PowerShell 5.1 (o que vem no Windows) e no PowerShell 7. Usa NTFS e **Robocopy reais**; só a identificação física do HD USB é simulada, porque o servidor de testes não tem HD USB.

| Arquivo | O que cobre |
|---|---|
| `tests\Backup.Tests.ps1` | Ponta a ponta: simulação sem gravar; primeiro backup (acentos, Unicode, arquivo vazio, oculto, 9 MB); exclusões; segunda execução sem leituras; alteração com versão anterior guardada; arquivo apagado continua no HD; pasta renomeada movida no HD; conferência sem manifesto e correção de cópia corrompida; manifesto adulterado; verificação de integridade (completa e por amostra); cópia interrompida; junção não seguida; arquivo só na nuvem (atributo Offline) não copiado; arquivo travado por outro programa; caminhos com mais de 260 caracteres; migração das pastas `AUTO_` da versão 1; falta de espaço; trava contra duas execuções; motor nativo (padrões, tags de reparse, SHA-256 igual ao `Get-FileHash`) |
| `tests\Config.Tests.ps1` | Leitura do `configuracao.txt` (UTF-8 com/sem BOM, UTF-16, ANSI), validação com todos os erros juntos, nomes, troca de destino, importação do `backup.local.json` e nome `AUTO_` da versão 1 |
| `tests\Destino.Tests.ps1` | Regras do HD (USB, NTFS, sistema, somente leitura, mesmo disco físico, raiz) e localização do HD quando a letra muda |
| `tests\Cli.Tests.ps1` | `Backup.ps1` em processo novo: códigos de saída, mensagens e recusa de destino que não é USB sem criar nada |
| `tests\Update.Tests.ps1` | `Atualizar.cmd`: recusa instalação ZIP, atualiza `main` só em fast-forward, preserva `configuracao.txt`, recusa alterações locais |
| `tests\Comparar-Desempenho.ps1` | Mede tempos (primeiro backup, sem mudanças, 10 alterados) e compara com a versão 1; o resultado aparece como anotação no CI |

## Rodar no seu computador

```powershell
Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -Force -SkipPublisherCheck
Invoke-Pester .\tests -Output Detailed
.\tests\Comparar-Desempenho.ps1 -Arquivos 3000
```

Os testes usam apenas pastas temporárias; não tocam no seu HD nem nas suas pastas.

## Roteiro manual com o seu HD (o CI não consegue fazer)

Faça uma vez, com dados de teste, antes de confiar o backup a dados importantes:

1. **HD recusado:** tente configurar um pendrive em exFAT ou um segundo disco interno — deve aparecer “não serve” com o motivo.
2. **Primeiro backup** de uma pasta pequena; abra o relatório e alguns arquivos direto do HD.
3. **Letra trocada:** em Gerenciamento de Disco, mude a letra do HD (ou conecte em outra porta) e rode o backup — deve encontrar o HD sozinho.
4. **HD removido no meio:** comece um backup grande e desconecte o HD (com cuidado) — deve parar com “INTERROMPIDO”; reconecte e rode de novo.
5. **OneDrive:** marque uma pasta como “Liberar espaço” — os arquivos devem aparecer como “Só na nuvem”, sem download.
6. **Agendamento:** agende para daqui a 2 minutos com o HD desconectado — deve aparecer o aviso; conecte e repita.
7. **Restauração:** restaure uma pasta para um local vazio e compare (`Get-FileHash`) com o original.
