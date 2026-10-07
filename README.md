# Windows Backup

Projeto pré-formatação baseado na pesquisa **Backup Windows com PowerShell: inventário profundo, deduplicação, segurança e verificação pré-formatação**, de 07/10/2026.

## Guia para quem está começando

### 1. Dependências

Windows 10/11 e Windows PowerShell 5.1 ou superior. O Robocopy acompanha o Windows e é necessário para copiar; o código verifica sua presença antes do modo Backup. O modo Audit não precisa dele.

Git é necessário apenas para clonar e atualizar o projeto. Baixe o instalador em https://git-scm.com/download/win e abra uma nova janela do PowerShell depois da instalação. Pandoc, Python e Node.js não são necessários. Pester 5.7.1 é dependência apenas dos testes de desenvolvimento.

### 2. Clonar o repositório

Abra o menu Iniciar, procure **Windows PowerShell** e abra normalmente. Cole este bloco uma vez. Ele cria uma pasta Projetos no seu perfil e baixa o código público para ela:

```powershell
New-Item -ItemType Directory -Path "$env:USERPROFILE\Projetos" -Force | Out-Null
cd "$env:USERPROFILE\Projetos"
git clone https://github.com/eduardoapgomes/windows-backup-audit.git
cd .\windows-backup-audit
```

Se a pasta já existe porque você clonou antes, use este bloco para atualizar, preservando sua configuração local:

```powershell
cd "$env:USERPROFILE\Projetos\windows-backup-audit"
git pull --ff-only
```

Alternativa sem Git: no repositório, clique **Code → Download ZIP**, extraia o ZIP e abra o PowerShell na pasta que contém Backup.ps1.

### 3. Configurar as pastas

Conecte o disco de backup. Execute este bloco apenas na primeira configuração; depois edite backup.local.json diretamente para não sobrescrever suas escolhas:

```powershell
cd "$env:USERPROFILE\Projetos\windows-backup-audit"
Copy-Item .\backup.example.json .\backup.local.json
notepad .\backup.local.json
```

Em **Destination**, informe a pasta do disco externo. Em **Sources**, informe as pastas que quer examinar/copiar. Cada **Id** deve ser único. Exemplo JSON (substitua USUARIO e a letra E; barras invertidas em JSON são duplicadas):

```json
{
  "Destination": "E:\\BACKUP_WINDOWS\\MEU-PC",
  "Sources": [
    {"Id": "01_DOCUMENTOS", "Path": "C:\\Users\\USUARIO\\Documents"},
    {"Id": "02_DOWNLOADS", "Path": "C:\\Users\\USUARIO\\Downloads"}
  ]
}
```

Inclua outras pastas necessárias. Para saber o caminho real de uma pasta, abra-a no Explorador e copie a barra de endereço. Documentos/Área de Trabalho podem estar dentro do OneDrive. Selecione pastas reais em vez do perfil inteiro, que pode conter junctions. O destino deve ficar fora de todas as origens.

### 4. Fazer somente a auditoria

Este bloco gera inventário e relatório; **não copia seus arquivos**:

```powershell
cd "$env:USERPROFILE\Projetos\windows-backup-audit"
.\Backup.ps1 -Mode Audit
```

O console informa a pasta do relatório. Vá até ela e dê dois cliques em **LEIA-ME.html** para ler no navegador, sem instalar nada. Também há LEIA-ME.md, inventario.csv e resumo.json. Se houve erro, haverá erros.txt ou mensagens na coluna Error.

O relatório lista as origens, quantidade, tamanho lógico, status, erros e passos de revisão. Abra inventario.csv no Excel para verificar os arquivos. **AUDITED significa encontrado, não salvo nem validado por hash.** Pastas não configuradas não foram examinadas. Uma pasta com erro pode ter sido examinada apenas parcialmente.

Revise origens, arquivos esperados e erros antes de passar ao próximo bloco. Consulte [cobertura](docs/COVERAGE.md) para aplicativos e dados especiais.

### 5. Fazer o backup de fato

Execute separadamente, depois de revisar a auditoria:

```powershell
cd "$env:USERPROFILE\Projetos\windows-backup-audit"
.\Backup.ps1 -Mode Backup
```

Leia o **novo** LEIA-ME.html. VERIFIED significa cópia conferida por SHA-256; SKIP_IDENTICAL significa que o destino já tinha o conteúdo; ERROR exige correção. Em reexecuções, arquivos idênticos não são recopiados.

Se o PowerShell bloquear scripts, consulte a política do computador; não desative proteções globalmente. Em computador pessoal, você pode usar RemoteSigned apenas nesta janela, se permitido:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
```

Depois repita o bloco de auditoria ou backup escolhido. Políticas de organização podem impedir essa alteração. O primeiro comando executável de Backup.ps1 é cd $PSScriptRoot.

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

Os relatórios ficam em `DESTINO\_RELATORIOS\ID_EXECUCAO`. Abra `LEIA-ME.html` para revisão guiada, `LEIA-ME.md`, `resumo.json`, `inventario.csv` e, se existir, `erros.txt`. O destino tem um lock exclusivo para impedir execuções simultâneas. Não há `/MIR`, `/PURGE`, exclusão da origem nem envio automático a IA.

Configure as raízes explicitamente. Uma raiz de disco como `D:\` pode ser auditada, mas diretórios protegidos/reparse geram erros. Um perfil completo pode conter junctions: nesses casos selecione separadamente as pastas reais. `Audit` não descobre sozinho todos os discos ou aplicativos. Veja [cobertura](docs/COVERAGE.md).

## Testes

```powershell
cd "$env:USERPROFILE\Projetos\windows-backup-audit"
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
