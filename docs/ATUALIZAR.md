# Instalar e atualizar — Windows 10/11

**Use a branch `main`.** Não é preciso Python nem permissões de administrador. O programa usa o Windows PowerShell 5.1 e o Robocopy, que já vêm no Windows (funciona também no PowerShell 7).

## Instalar com ZIP (mais simples)

1. Baixe o [ZIP da versão atual](https://github.com/eduardoapgomes/windows-backup-audit/archive/refs/heads/main.zip).
2. Clique com o botão direito › **Extrair tudo** e escolha uma pasta fixa, por exemplo `Documentos\windows-backup-audit`. **Extraia a pasta inteira**; não copie arquivos soltos.
3. Confira que `Iniciar.cmd`, `Backup.ps1` e a pasta `src` estão juntos.
4. Abra `Iniciar.cmd` e siga o [Guia rápido](GUIA-RAPIDO.md).

## Instalar com Git (atualização em um clique)

Instale o [Git para Windows](https://git-scm.com/downloads/win) e, no PowerShell:

```powershell
New-Item -ItemType Directory -Force "$env:USERPROFILE\Projetos" | Out-Null
Set-Location "$env:USERPROFILE\Projetos"
git clone --branch main https://github.com/eduardoapgomes/windows-backup-audit.git
Set-Location .\windows-backup-audit
.\Iniciar.cmd
```

Se a pasta já existe, **não rode `git clone` de novo dentro dela**: atualize.

## Atualizar

- **Instalação Git:** feche o programa e dê dois cliques em **`Atualizar.cmd`**. Ele só atualiza a `main` com `git pull --ff-only`, recusa se você tiver alterado arquivos do programa e **não mexe** em `configuracao.txt` nem no HD.
- **Instalação ZIP:** baixe o ZIP novo, extraia **em uma pasta nova** e copie para ela apenas o seu `configuracao.txt`. Não misture arquivos de versões diferentes.

O agendamento aponta para o `Backup.ps1` da pasta onde foi criado. Se mudar o programa de pasta, abra **5 – Agendar** de novo na pasta nova.

## Vindo da versão 1

A versão 2 é mais simples e usa outra configuração (`configuracao.txt` em vez de `backup.local.json`), mas **aproveita o backup que já está no HD**:

1. Atualize (Git) ou extraia a versão nova em uma pasta nova (ZIP) e copie para ela o seu `backup.local.json`, se você usava o modo manual.
2. Abra `Iniciar.cmd` › **4 – Configurar**. Se existir `backup.local.json`, as pastas são **importadas com os mesmos nomes** usados no HD. Caso contrário, o programa sugere as pastas pessoais.
3. Escolha o **mesmo HD**. O caminho padrão (`BACKUP_WINDOWS\<COMPUTADOR>-<USUÁRIO>`) é o mesmo da versão 1.
4. Faça o primeiro backup. O programa:
   - renomeia no próprio HD as pastas `AUTO_…` da descoberta automática para os nomes novos (por exemplo, `AUTO_3F2A…` → `Documents`), sem copiar nada;
   - **confere por SHA-256** os arquivos que já estão no HD, em vez de copiá-los de novo (por isso o primeiro backup lê tudo uma vez; os seguintes são rápidos);
   - copia o que faltar. Arquivos que a versão 1 tinha “reaproveitado” de outro lugar do HD (`REUSED_EXISTING`) são copiados para o caminho certo.

As pastas antigas `_RELATORIOS`, `.history-*` e `.stage-*` da versão 1 não são apagadas nem usadas; você pode guardá-las ou apagá-las manualmente depois de conferir o novo backup.

O que saiu na versão 2 (auditoria sem cópia, mapa visual, MinHash/LSH, Merkle) e por quê: [Como funciona](COMO-FUNCIONA.md#decisões-a-partir-do-relatório-de-pesquisa) e [CHANGELOG](../CHANGELOG.md). Quem precisar da versão 1 pode baixá-la do histórico do repositório (commit `46dad4d`).

## Problemas

**“o arquivo src\Backup.Core.psm1 não foi encontrado” / “Backup.ps1 não foi encontrado”.** A instalação está incompleta ou o `Iniciar.cmd` foi copiado sozinho. Extraia o ZIP inteiro em uma pasta nova.

**Atualizar.cmd diz “branch diferente de main”.** Rode `git switch main` na pasta do programa e tente de novo. Se não souber avaliar as alterações locais, faça um clone novo em outra pasta.

**Atualizar.cmd diz “há modificações locais”.** Você (ou alguém) alterou arquivos do programa. Nada foi descartado. Faça um clone novo em outra pasta e copie só o `configuracao.txt`. **Não use `git reset --hard`.**

**“O Windows protegeu o computador” ou “a execução de scripts está desabilitada”.** O `Iniciar.cmd` já chama o PowerShell com `-ExecutionPolicy Bypass` só para este programa. Se o SmartScreen avisar, clique em **Mais informações › Executar assim mesmo**. Arquivos baixados podem ser desbloqueados em Propriedades › **Desbloquear**.

Para ver qual versão está instalada (Git): `git log -1 --oneline`. Os testes de cada versão estão na aba [Actions](https://github.com/eduardoapgomes/windows-backup-audit/actions).

[Guia rápido](GUIA-RAPIDO.md) · [Página principal](../README.md)
