# Restaurar arquivos

O backup é uma **cópia comum de pastas**. Não precisa deste programa para ler: qualquer computador com Windows (ou Mac/Linux com leitura NTFS) abre o HD.

```text
E:\BACKUP_WINDOWS\MEU-PC-ana\
├── Documents\                 ← seus arquivos, na mesma estrutura do computador
├── Pictures\
├── _VERSOES_ANTERIORES\       ← versões antigas, por data do backup em que foram substituídas
└── _CONTROLE\                 ← manifestos e relatórios (não precisa mexer)
```

## Um arquivo ou uma pasta

1. Conecte o HD e abra a pasta do backup no Explorador de Arquivos.
2. Encontre o arquivo na pasta correspondente (por exemplo, `Documents\Contratos\aluguel.pdf`).
3. **Copie** (não mova) para onde quiser no computador.

## Uma versão anterior

Quando um arquivo mudou, a versão que estava no backup foi para `_VERSOES_ANTERIORES\<data>\<pasta>\...`, onde `<data>` é a data do backup em que ela foi substituída. Exemplo: a versão de `Documents\planilha.xlsx` que existia antes do backup de 13/10/2026 está em `_VERSOES_ANTERIORES\2026-10-13_20-00-05\Documents\planilha.xlsx`.

Dica: na caixa de pesquisa do Explorador, dentro de `_VERSOES_ANTERIORES`, digite o nome do arquivo para ver todas as versões guardadas.

## O computador inteiro (Windows novo ou formatado)

Pelo Explorador: copie cada pasta do HD de volta para o lugar correspondente (por exemplo, o conteúdo de `Documents` para a pasta Documentos do novo usuário).

Pelo PowerShell, com o Robocopy, sem nunca sobrescrever o que já existe no computador:

```powershell
robocopy "E:\BACKUP_WINDOWS\MEU-PC-ana\Documents" "C:\Users\ana\Documents" /E /COPY:DAT /DCOPY:DAT /XC /XN /XO /MT:8
robocopy "E:\BACKUP_WINDOWS\MEU-PC-ana\Pictures"  "C:\Users\ana\Pictures"  /E /COPY:DAT /DCOPY:DAT /XC /XN /XO /MT:8
```

**Nunca use `/MIR` ou `/PURGE` para restaurar**: eles apagam no destino o que não existe na origem.

Depois da restauração, os arquivos recebem as permissões da pasta onde foram colocados (o backup não copia permissões).

## Conferir que um arquivo restaurado está íntegro

Cada pasta tem um manifesto em `_CONTROLE\manifestos\<pasta>.tsv` com o SHA-256 de cada arquivo. Para conferir:

```powershell
Get-FileHash "C:\Users\ana\Documents\Contratos\aluguel.pdf"
Select-String -Path "E:\BACKUP_WINDOWS\MEU-PC-ana\_CONTROLE\manifestos\Documents.tsv" -Pattern "aluguel.pdf" -SimpleMatch
```

O valor de `Hash` (em maiúsculas) deve ser igual ao da coluna `sha256` (em minúsculas).

Para conferir o HD inteiro de uma vez, use **Verificar integridade** no menu.

## Teste de restauração (recomendado)

De vez em quando — e **sempre antes de formatar o computador** — escolha alguns arquivos importantes (um documento, uma foto, um projeto), copie do HD para uma pasta vazia e abra cada um no programa de costume. Um backup só é confiável depois de restaurado com sucesso.
