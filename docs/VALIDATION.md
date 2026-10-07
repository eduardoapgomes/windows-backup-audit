# Validação

Em 07/10/2026, **47 testes passaram, 0 falhas, 0 ignorados**, em Windows Server 2025 com Windows PowerShell 5.1 e Robocopy real.

- Commit de código testado: 112d1cd1bb535c26a673eb5747c2287a8f42a0de
- Execução: https://github.com/eduardoapgomes/windows-backup-audit/actions/runs/37673392742

## Cobertura executada

- Descoberta automática com metadados simulados: volumes internos de sistema/dados incluídos; USB excluído como origem; pastas redirecionadas, consolidação de raízes, identificadores estáveis e falhas de descoberta registradas.
- Enumeração com junction real: continuação pelas demais pastas e respeito a exclusões explícitas; destino continua interrompendo diante de índice incompleto.
- SHA-256 em blocos: arquivos vazio e de múltiplos blocos comparados com Get-FileHash; eventos intermediários de progresso verificados.
- Relatório HTML: tabelas, totais, cobertura, arquivos grandes e escape de caminhos; snapshots parciais com contadores, atualização e encaminhamento ao relatório final.
- CLI automática com e sem configuração manual, sem sobrescrever a configuração existente.

- Política física com metadados simulados: USB distinto permitido; interno/sistema, partição no mesmo disco, readonly, identidade alterada, identificação ausente, erro de leitura e formato incompatível bloqueados.
- Cloud Files: 16 tags permitidas somente em origens; tags desconhecidas bloqueadas; leitura nativa de metadados; arquivos offline/recall rejeitados antes do hash; falhas registradas no relatório sem cópia.
- CLI em processo Windows PowerShell novo: configuração padrão, caminho relativo, configuração ausente com mensagem acionável e encaminhamento do assistente. Configuração pessoal existente preservada.
- Caminhos: limites de diretório, UNC/relativos/ADS e junctions em ancestrais.
- Integração de arquivos em pastas temporárias: auditoria sem cópia, hash, reutilização de backup manual com outro nome, cópia só do que falta, reexecução, detecção de alteração com mesmo tamanho/timestamp, preservação da versão anterior, falta de espaço simulada, corrupção simulada e lock concorrente.
- Restauração de dois caminhos lógicos a partir de uma única cópia reutilizada, usando o inventário e validando os hashes restaurados.
- Dependências, configuração vazia/identificadores reservados e relatório com HTML escapado.

Somente a política física é substituída por um mock nos testes de arquivos: runners não têm HD USB. Os testes da política usam metadados sintéticos e não comprovam como cada controlador físico se identifica.

## Validação manual necessária

Varredura completa do computador do usuário, atualização automática do HTML no navegador, OneDrive real (arquivos locais e somente online), assistente gráfico de configuração, menu Iniciar.cmd, abertura do relatório no navegador, janela de seleção/cancelamento, acesso ao módulo Storage, reconhecimento do seu USB/NTFS, desconexão/troca física, bloqueio do disco interno no hardware real, caminhos longos e restauração dos seus documentos nos aplicativos originais. Não executar ensaios destrutivos sobre dados únicos.

A referência da pesquisa foi renomeada para Research-Backup.ps1.txt e não é ponto de entrada executável do projeto. Não houve validação integral daquele texto.

O utilitário é um backup de arquivos configurados, não uma imagem do sistema ou snapshot transacional. Consulte [segurança e retomada](SAFETY.md).
