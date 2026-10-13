# Instalar e atualizar — Windows 10/11

**Use somente a branch `main` como versão de uso.** Não é necessário criar fork, instalar Python ou usar branches de desenvolvimento para fazer backup. O programa usa Windows PowerShell 5.1, já disponível no Windows 10/11.

## Primeira instalação (recomendado: Git)

Instale o [Git para Windows](https://git-scm.com/downloads/win) se ainda não estiver disponível. Abra **PowerShell** e execute:

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\Projetos" | Out-Null
Set-Location "$env:USERPROFILE\Projetos"
git clone --branch main https://github.com/eduardoapgomes/windows-backup-audit.git
Set-Location .\windows-backup-audit
Test-Path .\Backup.ps1
Test-Path .\src\Backup.Core.psm1
.\Iniciar.cmd
```

Os dois testes devem mostrar **True**. Se a pasta já existe, **não execute `git clone` por cima dela**: siga a seção de atualização.

Conecte um HD/SSD **USB externo NTFS**, em disco físico diferente do computador. No menu, use **1 — Auditoria focada**, revise `LEIA-ME.html` e `cobertura.csv`; depois use **2 — Backup focado**, selecionando o mesmo destino. Teste a restauração. A opção 3 permite escolher outras pastas.

## Atualizar uma instalação Git

Feche o menu, a auditoria e o backup. Dentro da pasta do programa, **dê dois cliques em `Atualizar.cmd`**. Ele:

- Atualiza **somente `main`**, usando `git pull --ff-only origin main`.
- Para se houver alterações locais em arquivos versionados ou se a branch atual não for `main`; **não usa `reset --hard` nem `clean`**.
- Confere a existência de `Backup.ps1` e `src\Backup.Core.psm1` após atualizar.
- Não toca no HD USB nem no arquivo pessoal `backup.local.json` (ignorado pelo Git).

Se preferir o terminal, dentro da pasta clonada:

```powershell
git status --short
git branch --show-current
git pull --ff-only origin main
Test-Path .\Backup.ps1
Test-Path .\src\Backup.Core.psm1
.\Iniciar.cmd
```

**Importante:** `git pull` não é uma reinstalação. Se `Backup.ps1` foi apagado localmente, o Git pode recusar a atualização. Não force nem apague arquivos: use uma pasta nova, como descrito abaixo.

## Instalar/atualizar sem Git (ZIP)

1. Baixe o [ZIP da versão principal](https://github.com/eduardoapgomes/windows-backup-audit/archive/refs/heads/main.zip).
2. **Extraia a pasta inteira em uma pasta nova** (por exemplo, `Projetos\windows-backup-audit-novo`). Não copie apenas `Iniciar.cmd` e não misture versões.
3. Confirme que **`Iniciar.cmd`, `Backup.ps1` e `src\Backup.Core.psm1`** existem na mesma instalação.
4. Se você usa o modo manual, copie **somente `backup.local.json`** da instalação anterior para a nova e confira os caminhos no arquivo. Não envie esse arquivo ao GitHub.
5. Abra `Iniciar.cmd`. Se o backup já existe, selecione **a mesma pasta do HD USB** para revalidar/reutilizar cópias. **Não apague o backup anterior**.

`Atualizar.cmd` informa o endereço do ZIP quando a pasta não é um clone Git; não sobrescreve instalações ZIP automaticamente.

## Erro: “Backup.ps1 não existe”

Esse erro significa **instalação incompleta ou menu aberto na pasta errada**. A auditoria não começou.

No PowerShell, dentro da pasta que contém `Iniciar.cmd`:

```powershell
Get-Location
Test-Path .\Backup.ps1
Test-Path .\src\Backup.Core.psm1
Get-ChildItem -Path . -Filter Backup.ps1 -Recurse -File | Select-Object -ExpandProperty FullName
```

Se aparecer `Backup.ps1` numa subpasta, abra o `Iniciar.cmd` **daquela mesma subpasta**. Se não existir, reinstale em pasta nova. O menu atualizado detecta esse problema e **não mostra falso sucesso**.

## Problemas de atualização

- **Branch diferente de `main`:** verifique `git status --short`; se não houver alterações que precise guardar, execute `git switch main` e tente `Atualizar.cmd` novamente. Se não souber avaliar alterações, faça um clone novo em outra pasta.
- **Arquivos versionados modificados:** `Atualizar.cmd` recusa o pull para preservar seu trabalho. Faça um clone novo ou resolva as mudanças conscientemente; **não use `git reset --hard`**.
- **Git não instalado:** use o ZIP ou instale Git para Windows. O programa de backup não depende de Git para executar.
- **Sem internet:** a atualização não funciona; o backup local continua disponível. Não execute versões misturadas.
- **Energia acabou:** relatórios parciais não são confirmação de backup. Guarde os arquivos existentes no USB, atualize o programa em uma pasta íntegra e faça uma nova auditoria antes de copiar.

Para ver qual commit está instalado numa cópia Git, use `git log -1 --oneline`. O histórico e a validação estão na aba [Actions](https://github.com/eduardoapgomes/windows-backup-audit/actions) do repositório. Testes automáticos **não substituem** um teste de restauração com o seu HD USB.

[Voltar ao guia rápido](GUIA-RAPIDO.md) · [Segurança](SAFETY.md) · [Página principal](../README.md)
