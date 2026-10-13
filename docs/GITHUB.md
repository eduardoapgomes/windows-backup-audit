# Manutenção do repositório

Repositório único: https://github.com/eduardoapgomes/windows-backup-audit

**Para usar o programa, acompanhe apenas a branch `main`.** Branches de desenvolvimento não são forks nem instalações alternativas. Uma alteração passa por pull request, testes automáticos e integração à `main`. A integração por **squash** mantém um commit de entrega simples na `main`, mesmo que o desenvolvimento tenha usado vários commits.

O workflow [Windows tests](https://github.com/eduardoapgomes/windows-backup-audit/actions) roda em pull requests direcionados à `main`, nos commits enviados à `main` e manualmente. Usa Pester no Windows PowerShell 5.1 e testes Python. CI aprovada não substitui teste físico com HD USB e restauração real.

Para atualizar sua instalação, **não é necessário criar fork nem mudar de branch**. Use [Atualizar.cmd e o guia de instalação](ATUALIZAR.md).

## Cuidados de publicação

Código, documentação e testes são públicos (MIT). Não publique `backup.local.json`, relatórios de backup, nomes/caminhos pessoais, chaves ou certificados. Não altere backups existentes nem faça `git reset --hard` como procedimento de atualização. O arquivo `backup.local.json` é ignorado pelo Git.

Se precisar trabalhar numa mudança futura, crie uma branch temporária, teste e faça um PR para `main`. Não publique mudanças não validadas diretamente na versão de uso.
