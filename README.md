# Windows Backup

Projeto pré-formatação baseado na pesquisa **Backup Windows com PowerShell: inventário profundo, deduplicação, segurança e verificação pré-formatação**, de 07/10/2026.

## Início rápido

Requisitos: Windows 10/11, Windows PowerShell 5.1, Robocopy e mídia externa acessível. Extraia o projeto em `C:\BackupWindows`. Abra PowerShell nessa pasta. Não copie o exemplo sem corrigir os caminhos.

```powershell
cd C:\BackupWindows
Copy-Item .\backup.example.json .\backup.local.json
notepad .\backup.local.json
.\Backup.ps1 -Mode Audit
# Depois de revisar os caminhos e o inventário:
.\Backup.ps1 -Mode Backup
```

Se a política impedir scripts, use uma política aprovada no seu computador; não desative proteções globalmente. O primeiro comando executável do ponto de entrada é `cd $PSScriptRoot`.

## Comportamento

| Operação | Resultado |
|---|---|
| Audit | Metadados locais; não copia os arquivos de origem |
| Backup | Hash, cópia em staging, verificação e instalação |
| Reexecução | Mesmo conteúdo no mesmo destino: SKIP_IDENTICAL |
| Conteúdo alterado | Preserva versão anterior em `.history-*` ao lado do arquivo |
| Erro de leitura/cópia | Registra erro, resumo e retorno 2 |
| Raízes sobrepostas | Processa cada caminho de origem uma vez; primeira raiz prevalece |
| Arquivos iguais em locais diferentes | Preserva cada caminho |
| Junction/symlink/placeholder | Interrompe essa raiz e exige revisão explícita |

Os relatórios ficam em `DESTINO\_RELATORIOS\ID_EXECUCAO`. Abra `resumo.json`, `inventario.csv` e, se existir, `erros.txt`. O destino tem um lock exclusivo para impedir execuções simultâneas. Não há `/MIR`, `/PURGE`, exclusão da origem nem envio automático a IA.

Configure as raízes explicitamente. Uma raiz de disco como `D:\` pode ser auditada, mas diretórios protegidos/reparse geram erros. Um perfil completo pode conter junctions: nesses casos selecione separadamente as pastas reais. `Audit` não descobre sozinho todos os discos ou aplicativos. Veja [cobertura](docs/COVERAGE.md).

## Testes

```powershell
cd C:\BackupWindows
Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -Force
Invoke-Pester .\tests -Output Detailed
```

Há integração com Robocopy real para reexecução idempotente, alteração de conteúdo com tamanho e timestamp iguais e retenção anterior, além de validação de caminhos e modo auditoria. CI em `.github/workflows/tests.yml`. Consulte [validação](docs/VALIDATION.md) antes de uso real.

## Restauração

Copie uma amostra do destino para uma pasta vazia fora das origens, compare SHA-256 com o inventário e abra os arquivos no aplicativo original. Inclua documento, fotografia e projeto. Para recuperar versão anterior, examine `.history-*`; os nomes são únicos e não indicam sozinhos o arquivo original, portanto mantenha o contexto da pasta e confira conteúdo/hash. Não existe comando automático de restauração nem índice de versões nesta versão.

## Limites

Não é imagem de sistema, snapshot VSS nem backup transacional. Feche aplicativos e faça exports nativos de bancos/WSL/Docker/VMs. Não garante ACLs, alternate data streams, EFS, certificados privados ou recuperação de sessões de navegador. Verificação de hash não comprova consistência de banco nem ausência de malware. Caminhos longos, FAT32, arquivos bloqueados e pouco espaço podem falhar e devem ser testados na mídia real. Use somente destino sem junctions/symlinks e confiável: o motor não protege contra alterações concorrentes maliciosas da árvore de destino. `File.Replace` precisa de suporte do filesystem; em caso de falha preserva o destino anterior e registra erro.

O script não determina se é seguro formatar. Antes disso: cobertura revisada, nenhum erro pendente, exports especiais testados, segunda cópia independente e teste real de restauração. Criptografe mídia com dados sensíveis e mantenha recovery keys em outro local.

## Publicação

O repositório público deve conter somente código, testes e documentação. Nunca envie `backup.local.json`, relatórios, dados, chaves ou exports. O `.gitignore` é uma barreira auxiliar, não um scanner de segredos. Veja [publicação](docs/GITHUB.md).

## Organização

`src/Backup.Core.psm1`: funções de caminhos, enumeração, hash, transporte e coordenação. `Backup.ps1`: CLI/configuração. `tests`: contratos e integração. `reference/Research-Backup.ps1`: implementação extensa da pesquisa, preservada para referência, com correção de expansão de `$RECYCLE` e transporte forçado após decisão de hash; experimental, não validada e não usada pelo motor modular.

O projeto adapta recomendações da pesquisa; não apresenta o script extenso como produção testada. Licença MIT; consulte LICENSE.
