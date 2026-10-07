# Cobertura e preparação

| Dados | Ação |
|---|---|
| Desktop/Documentos/Imagens/Downloads | Usar caminhos reais, inclusive redirecionamentos de OneDrive |
| Outros discos/ProgramData/customizados | Auditar raízes e revisar erros; selecionar dados para cópia |
| OneDrive | Marcar arquivos importantes para manter neste dispositivo antes da cópia |
| SSH/GPG/vaults | Incluir raízes reais; conferir recuperação e criptografia |
| Outlook/Thunderbird/Zotero | Fechar apps; incluir perfil completo e anexos; testar abertura |
| WSL | Exportar cada distro com `wsl --export`, incluir export e testar `wsl --import` |
| Docker/n8n | Backup de volumes, configuração e encryption key; parar workloads e gerar dumps consistentes |
| Hyper-V/VMware/VirtualBox | Export nativo ou procedimento do fabricante; testar import |
| SQL/Postgres/MySQL/SQLite | Backup nativo consistente, não apenas arquivo do banco ativo |
| Certificados/EFS/BitLocker/MFA | Export/recovery conforme produto; armazenamento separado e teste |
| Navegadores/licenças | Exportar favoritos, conferir conta/sync/reativação; perfil não garante senhas portáveis |
| Git | Conferir branches/commits locais, untracked, submodules e LFS |

O motor modular copia arquivos explicitamente configurados. As integrações automáticas mais amplas do relatório permanecem na referência experimental. Esta tabela exige revisão humana e não promete cobertura universal.

Fontes primárias para revisão:
- https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/robocopy
- https://learn.microsoft.com/en-us/windows/wsl/basic-commands
- https://docs.docker.com/engine/storage/volumes/
- https://www.cisa.gov/stopransomware/ransomware-guide
- https://www.zotero.org/support/zotero_data
