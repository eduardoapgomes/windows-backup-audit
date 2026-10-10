# Cobertura: o que proteger e o que revisar

**Regra:** proteger informação pessoal, não fazer imagem do Windows. O modo automático é **focado** e não promete cobrir todos os arquivos do computador.

| Local ou tipo | Comportamento recomendado |
|---|---|
| Documentos, Desktop, Downloads, Imagens, Música, Vídeos, Favoritos, OneDrive | Pastas conhecidas incluídas quando existem; confira redirecionamentos e arquivos de nuvem disponíveis localmente |
| Projetos, Code, Repos, Dados, Trabalho, Estudos e nomes semelhantes | Pastas reconhecidas no perfil e na raiz de volumes internos entram no escopo |
| Pastas com nomes diferentes, arquivos soltos em C:\ ou D:\, outras contas e Public | **REVIEW**: não auditados automaticamente; adicione manualmente as pastas que contêm dados importantes |
| Windows, Program Files, ProgramData, AppData, instalações e caches | **Não são selecionados como raízes automáticas.** Configurações e dados exclusivos de aplicativos precisam de seleção/exportação específica |
| node_modules, site-packages reconhecidos, __pycache__, .pytest_cache, .mypy_cache, .ruff_cache | Ignorados no padrão para evitar percorrer dependências e caches; use -DependencyPolicy Include quando houver conteúdo próprio ali |
| SSH, GPG, credenciais, chaves, vaults, certificados, BitLocker, MFA | Faça exportação/backup próprio, proteja com criptografia e teste a recuperação |
| Outlook, Thunderbird, Zotero e outros aplicativos | Feche o aplicativo e use exportação consistente; selecione perfis/dados reais manualmente |
| WSL, Docker, bancos, VMs | Use export/dump/snapshot suportado pelo produto, teste importação e inclua os arquivos exportados |
| Git | Verifique commits locais, branches, arquivos não rastreados, submódulos e LFS |

**Como revisar:** abra cobertura.csv. INCLUDED foi selecionado; COVERED está dentro de outra raiz; REVIEW indica local não examinado; NOT_FOUND indica pasta opcional ausente; ERROR exige correção. O relatório não infere se o que ficou de fora é dispensável.

Se você quer varrer uma pasta específica, use as opções 3–5 do menu. Selecionar manualmente uma raiz de disco inteiro é possível apenas sob as regras de segurança e pode ser muito lento; prefira a pasta que contém seus dados. O destino deve ser USB/NTFS, em disco físico diferente.

A auditoria automática rápida não calcula SHA-256 de arquivos novos sem candidatos de mesmo tamanho no destino. O modo Backup sempre usa verificação por conteúdo. Veja [guia rápido](GUIA-RAPIDO.md), [segurança](SAFETY.md) e [Merkle/MinHash](INCREMENTAL.md).

Referências: [Windows Known Folders](https://learn.microsoft.com/en-us/windows/win32/shell/knownfolderid), [Robocopy](https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/robocopy), [WSL](https://learn.microsoft.com/en-us/windows/wsl/basic-commands), [Docker volumes](https://docs.docker.com/engine/storage/volumes/).
