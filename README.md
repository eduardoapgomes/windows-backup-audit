# Windows Backup

## Comece pelo menu (Windows)

Se você já clonou o projeto, atualize sem recriar sua configuração:

```powershell
cd "$env:USERPROFILE\Projetos\windows-backup-audit"
git pull --ff-only
if ($LASTEXITCODE -ne 0) { throw "A atualização falhou; confira a mensagem acima." }
.\Iniciar.cmd
```

Também pode dar dois cliques em **Iniciar.cmd**. Escolha **1** apenas no primeiro uso para selecionar as pastas de origem em janelas. Uma configuração existente é preservada. Escolha **2** para auditar e abrir o relatório HTML; **3** para copiar e verificar; **4** para ler a documentação; **5** para editar sua configuração. Confira todas as pastas desejadas: a seleção não inclui automaticamente o computador inteiro.

Na seleção de destino, escolha o HD USB e depois a pasta onde estão os backups manuais/parciais. Para começar um backup novo, escolha a raiz do HD: o programa cria sua pasta própria. A auditoria grava relatórios no HD, mas não copia seus arquivos. Arquivos iguais são comparados por SHA-256 e reutilizados dentro da pasta selecionada.

### OneDrive

Pastas e arquivos com marcadores Cloud Files são aceitos **somente como origem**. Junctions, links e outros tipos de redirecionamento continuam bloqueados, mesmo dentro de uma pasta chamada OneDrive. O destino continua exigindo USB/NTFS, fora do disco de origem e sem reparse points.

Se aparecer **“Arquivo em nuvem não disponível localmente”**, no Explorador clique com o botão direito na pasta do OneDrive, escolha **Sempre manter neste dispositivo** e aguarde a conclusão do download. Isso usa espaço no disco de origem. Depois execute a auditoria novamente. O programa verifica atributos antes de ler e registra arquivos indisponíveis como erro; não baixa conteúdo deliberadamente nem considera esses arquivos protegidos pelo backup. Um provedor concorrente pode alterar o estado entre a verificação e a leitura; veja `docs/SAFETY.md`.

### Comandos separados (sem menu)

Configuração inicial por janelas, somente se ainda não tiver `backup.local.json`:

```powershell
powershell.exe -NoProfile -STA -File .\Backup.ps1 -Setup
```

**Auditoria — comparar e gerar relatório:**

```powershell
powershell.exe -NoProfile -STA -File .\Backup.ps1 -Mode Audit -SelectDestination -OpenReport
```

**Backup — copiar e verificar, após revisar a auditoria:**

```powershell
powershell.exe -NoProfile -STA -File .\Backup.ps1 -Mode Backup -SelectDestination -OpenReport
```

O relatório abre automaticamente quando a execução termina sem erros. Se houver erros, a mensagem indica a pasta `_RELATORIOS` no HD; abra seu `LEIA-ME.html`. Não reinstale nem formate o Windows com pendências. Não é necessário instalar Pandoc. O menu usa Windows PowerShell Desktop, Windows Forms e Out-GridView; a leitura de tags usa APIs nativas do Windows por `Add-Type` (ambientes com linguagem restrita podem bloquear, sem liberar o destino).


Projeto pré-formatação baseado na pesquisa **Backup Windows com PowerShell: inventário profundo, deduplicação, segurança e verificação pré-formatação**, de 07/10/2026.

## Guia para quem está começando

### 1. Dependências

Windows 10/11, Windows PowerShell Desktop 5.1 e módulo Storage (Get-Disk/Get-Partition/Get-Volume). A interface usa Out-GridView e Windows Forms. O destino precisa ser um USB externo NTFS. O Robocopy acompanha o Windows e é necessário para copiar; o código verifica sua presença antes do modo Backup. O modo Audit não precisa dele.

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

Deixe **Destination** vazio (`""`) para abrir a seleção de disco e pasta. Também pode informar uma pasta externa explicitamente; as mesmas validações são obrigatórias em ambos os casos. Em **Sources**, informe as pastas que quer examinar/copiar. Cada **Id** deve ser único. Exemplo JSON (substitua USUARIO; barras invertidas em JSON são duplicadas):

```json
{
  "Destination": "",
  "Sources": [
    {"Id": "01_DOCUMENTOS", "Path": "C:\\Users\\USUARIO\\Documents"},
    {"Id": "02_DOWNLOADS", "Path": "C:\\Users\\USUARIO\\Downloads"}
  ]
}
```

Inclua outras pastas necessárias. Para saber o caminho real de uma pasta, abra-a no Explorador e copie a barra de endereço. Documentos/Área de Trabalho podem estar dentro do OneDrive. Selecione pastas reais em vez do perfil inteiro, que pode conter junctions. O destino deve ficar fora de todas as origens.

### 4. Fazer somente a auditoria

Este bloco abre a seleção de mídia, compara conteúdo e gera relatório; **não copia seus arquivos**. Na segunda janela, escolha a pasta que já contém seu backup manual. Para um backup novo, selecione a raiz do USB e o programa usará BACKUP_WINDOWS\COMPUTADOR-USUARIO:

```powershell
cd "$env:USERPROFILE\Projetos\windows-backup-audit"
powershell.exe -NoProfile -STA -File .\Backup.ps1 -Mode Audit -SelectDestination
```

O console informa a pasta do relatório. Vá até ela e dê dois cliques em **LEIA-ME.html** para ler no navegador, sem instalar nada. Também há LEIA-ME.md, inventario.csv e resumo.json. Se houve erro, haverá erros.txt ou mensagens na coluna Error.

O relatório lista as origens, quantidade, tamanho lógico, status, erros e passos de revisão. Abra inventario.csv no Excel para verificar os arquivos. **NEEDS_COPY significa que ainda falta copiar. SKIP_IDENTICAL e REUSED_EXISTING indicam uma cópia encontrada e comparada por SHA-256.** Pastas não configuradas não foram examinadas. Uma pasta com erro pode ter sido examinada apenas parcialmente.

Revise origens, arquivos esperados e erros antes de passar ao próximo bloco. Consulte [cobertura](docs/COVERAGE.md) para aplicativos e dados especiais.

### 5. Fazer o backup de fato

Execute separadamente, depois de revisar a auditoria, escolhendo o mesmo disco e pasta:

```powershell
cd "$env:USERPROFILE\Projetos\windows-backup-audit"
powershell.exe -NoProfile -STA -File .\Backup.ps1 -Mode Backup -SelectDestination
```

Leia o **novo** LEIA-ME.html. VERIFIED significa cópia conferida por SHA-256; SKIP_IDENTICAL significa que o destino já tinha o conteúdo; REUSED_EXISTING indica uma cópia igual em outro caminho e ERROR exige correção. Em reexecuções, arquivos idênticos não são recopiados.

Se o PowerShell bloquear scripts, consulte a política do computador; não desative proteções globalmente. Em computador pessoal, você pode usar RemoteSigned apenas nesta janela, se permitido:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy RemoteSigned
```

Depois repita o bloco de auditoria ou backup escolhido. Políticas de organização podem impedir essa alteração. O primeiro comando executável de Backup.ps1 é cd $PSScriptRoot.

## Comportamento

| Operação | Resultado |
|---|---|
| Audit | Compara SHA-256 com cópias existentes; gera relatórios no USB |
| Backup | Hash, cópia em staging, verificação e instalação |
| Reexecução | Mesmo conteúdo no mesmo destino: SKIP_IDENTICAL |
| Conteúdo alterado | Preserva versão anterior em `.history-*` ao lado do arquivo |
| Erro de leitura/cópia | Registra erro, resumo e retorno 2 |
| Raízes sobrepostas | Processa cada caminho de origem uma vez; primeira raiz prevalece |
| Arquivos iguais em locais diferentes | Reutiliza conteúdo; Source → Destination no CSV preserva o mapeamento |
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

## Seleção segura e backup parcial

A interface só lista destinos USB/NTFS identificáveis, graváveis, sem boot/sistema e em disco físico diferente de todas as origens. SATA/NVMe internos, redes, volumes virtuais/ambíguos e outros formatos são bloqueados. Não há opção de ignorar essa regra nem formatação automática. Se o módulo Storage não conseguir confirmar a mídia, a execução para; confira acesso/permissões sem mudar o disco às cegas.

A varredura de cópias manuais cobre **a pasta escolhida e suas subpastas**, não todo o HD. Escolha uma pasta que englobe o backup parcial. O programa compara tamanho + SHA-256, mesmo com nome diferente. Não apaga duplicatas que já existiam. Falha ao indexar o destino impede o início da cópia.

Para conteúdo reutilizado, **Destination no inventario.csv aponta para o arquivo real**. PlannedDestination é o caminho que seria criado. Guarde os relatórios junto do backup e não mova/apague arquivos reutilizados. Um único arquivo pode atender várias origens; por isso a árvore do destino não necessariamente reproduz todas as árvores de origem. A auditoria pode ser demorada porque lê o conteúdo, inclusive de backups manuais.

Mais detalhes e limites: [segurança e retomada](docs/SAFETY.md).

## Restauração

Use a coluna Destination do inventário para localizar a cópia real, inclusive REUSED_EXISTING. Source e RootId/RelativePath indicam a origem lógica. Para recuperar vários caminhos com conteúdo igual, copie a mesma cópia para cada caminho em uma pasta de restauração vazia. Copie uma amostra do destino para uma pasta vazia fora das origens, compare SHA-256 com o inventário e abra os arquivos no aplicativo original. Inclua documento, fotografia e projeto. Para recuperar versão anterior, examine `.history-*`; os nomes são únicos e não indicam sozinhos o arquivo original, portanto mantenha o contexto da pasta e confira conteúdo/hash. Não existe comando automático de restauração nem índice de versões nesta versão.

## Limites

Não é imagem de sistema, snapshot VSS nem backup transacional. Feche aplicativos e faça exports nativos de bancos/WSL/Docker/VMs. Não garante ACLs, alternate data streams, EFS, certificados privados ou recuperação de sessões de navegador. Verificação de hash não comprova consistência de banco nem ausência de malware. Caminhos longos, arquivos bloqueados e pouco espaço podem falhar e devem ser testados na mídia real. O programa bloqueia redirecionamentos nos caminhos, verifica o disco físico e revalida sua identidade antes das gravações. Ainda exige um computador e uma mídia confiáveis; alterações concorrentes maliciosas não estão cobertas por uma garantia absoluta. `File.Replace` precisa de suporte do filesystem; em caso de falha preserva o destino anterior e registra erro.

O script não determina se é seguro formatar. Antes disso: cobertura revisada, nenhum erro pendente, exports especiais testados, segunda cópia independente e teste real de restauração. Criptografe mídia com dados sensíveis e mantenha recovery keys em outro local.

## Publicação

O repositório público deve conter somente código, testes e documentação. Nunca envie `backup.local.json`, relatórios, dados, chaves ou exports. O `.gitignore` é uma barreira auxiliar, não um scanner de segredos. Veja [publicação](docs/GITHUB.md).

## Organização

`src/Backup.Core.psm1`: funções de caminhos, enumeração, hash, transporte e coordenação. `Backup.ps1`: CLI/configuração. `tests`: contratos e integração. `reference/Research-Backup.ps1.txt`: implementação extensa da pesquisa, preservada para referência, com correção de expansão de `$RECYCLE` e transporte forçado após decisão de hash; referência textual não executável, não usada pelo motor modular.

O projeto adapta recomendações da pesquisa; não apresenta o script extenso como produção testada. Licença MIT; consulte LICENSE.
