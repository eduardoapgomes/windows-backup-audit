# Validação

Em 07/10/2026, **24 testes passaram, 0 falhas, 0 ignorados**, em Windows Server 2025 com Windows PowerShell 5.1 e Robocopy real.

- Commit de código testado: 8a405f1f8c3ad9e40168eb8563467db7bc3cff6c
- Execução: https://github.com/eduardoapgomes/windows-backup-audit/actions/runs/37638214713

## Cobertura executada

- Política física com metadados simulados: USB distinto permitido; interno/sistema, partição no mesmo disco, readonly, identidade alterada, identificação ausente, erro de leitura e formato incompatível bloqueados.
- Caminhos: limites de diretório, UNC/relativos/ADS e junctions em ancestrais.
- Integração de arquivos em pastas temporárias: auditoria sem cópia, hash, reutilização de backup manual com outro nome, cópia só do que falta, reexecução, detecção de alteração com mesmo tamanho/timestamp, preservação da versão anterior, falta de espaço simulada, corrupção simulada e lock concorrente.
- Restauração de dois caminhos lógicos a partir de uma única cópia reutilizada, usando o inventário e validando os hashes restaurados.
- Dependências, configuração vazia/identificadores reservados e relatório com HTML escapado.

Somente a política física é substituída por um mock nos testes de arquivos: runners não têm HD USB. Os testes da política usam metadados sintéticos e não comprovam como cada controlador físico se identifica.

## Validação manual necessária

Janela de seleção/cancelamento, acesso ao módulo Storage, reconhecimento do seu USB/NTFS, desconexão/troca física, bloqueio do disco interno no hardware real, caminhos longos e restauração dos seus documentos nos aplicativos originais. Não executar ensaios destrutivos sobre dados únicos.

A referência da pesquisa foi renomeada para Research-Backup.ps1.txt e não é ponto de entrada executável do projeto. Não houve validação integral daquele texto.

O utilitário é um backup de arquivos configurados, não uma imagem do sistema ou snapshot transacional. Consulte [segurança e retomada](SAFETY.md).
