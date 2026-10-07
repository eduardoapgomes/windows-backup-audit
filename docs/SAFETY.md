# Política de segurança e recuperação

## O que o programa exige

Destino em USB/NTFS, identificação única de disco e volume, mídia gravável e sem função de boot/sistema. Cada origem é resolvida para um disco físico; partições distintas do mesmo disco são rejeitadas. Caminhos relativos, UNC, ADS, junctions, links e mount points são rejeitados. A seleção por interface e a configuração manual passam pela mesma validação. Nenhuma opção permite desabilitá-la em produção.

O módulo Storage do Windows informa a identidade física e o BusType. Não existe detecção universal infalível de localização física: caixas USB incomuns, controladores e políticas de acesso podem impedir a identificação; nesse caso a execução para. Thunderbolt/eSATA que aparecem como NVMe/SATA também ficam bloqueados nesta versão. USB interno reportado pelo hardware como USB não pode ser universalmente distinguido de USB externo. Não se promete risco zero.

O script não formata, não altera partições e não escreve conteúdo nas origens. Lê origens para hash e cópia; efeitos normais do Windows/provedor, como cache e timestamps de acesso, podem ocorrer. Aplicações ativas devem ser fechadas. O lock de leitura protege cada cópia contra escritores concorrentes, mas não fornece snapshot de um conjunto de arquivos/banco.

## Gravações

Relatórios e cópias ficam no destino validado. A identidade do disco/volume e os ancestrais dos caminhos são reavaliados antes das gravações principais e da limpeza. Um lock exclusivo impede duas execuções no mesmo repositório. A cópia usa staging, hash pós-cópia e substituição com preservação anterior. Falha antes de instalar mantém a versão anterior. Falha/interrupção pode deixar staging; não apague pastas indiscriminadamente.

Há margem mínima de 16 MiB além do tamanho do arquivo em staging, verificada por cópia. Não é reserva de espaço nem previsão total. Na remoção/troca de mídia, o programa para; relatórios finais podem não ser gravados. Não desconecte durante a execução.

Um processo privilegiado hostil pode trocar caminhos entre uma checagem e um acesso (TOCTOU). Este utilitário não é uma barreira contra administrador/malware nem substitui solução de backup dedicada com snapshots e armazenamento imutável.

## Cópias parciais/manuais

O índice lista arquivos regulares sob a pasta selecionada; exclui relatórios, lock, staging e versões anteriores. O índice usa tamanho + SHA-256, calculado uma vez na varredura inicial. Cada candidato reutilizado é revalidado por SHA-256 antes da decisão, evitando confiar apenas no índice. Arquivo igual em outro caminho recebe REUSED_EXISTING e Destination aponta para a cópia real. Nenhum hard link é criado. Duplicatas preexistentes não são removidas.

O CSV é parte do backup: Source → Destination registra como reconstruir os caminhos. RelativePath começa com .\ para não virar fórmula ao abrir no Excel. Várias origens podem apontar para uma mesma cópia; não mova/apague essa cópia. O repositório precisa ser movido como conjunto com seus relatórios; os caminhos absolutos do CSV terão de ser ajustados para uma nova letra de disco na restauração. Não há restauração automatizada nesta versão.

Se a indexação falhar, nenhuma cópia é iniciada. Um erro na enumeração de origem deixa essa raiz incompleta e é reportado; a execução termina com erro. Verifique erros e arquivos esperados, não apenas a contagem.

## Testes e limites de cobertura

Os testes Windows usam Robocopy real em pastas temporárias. Somente nesses testes de arquivo a política física é simulada, pois runners não têm HD USB. Testes separados verificam a política com metadados sintéticos: USB permitido, disco interno/sistema bloqueado, partições no mesmo disco, identidade alterada, volume desconhecido, readonly e filesystem não suportado.

O comportamento de dispositivos reais e da janela gráfica requer teste manual com seu hardware. Verifique: seleção e cancelamento, USB removido, troca de letra, disco interno, falta de espaço e restauração de arquivos reutilizados. Os testes automatizados não comprovam esses cenários físicos.

Fontes primárias consultadas:
- https://learn.microsoft.com/en-us/powershell/module/storage/get-disk
- https://learn.microsoft.com/en-us/powershell/module/storage/get-partition
- https://learn.microsoft.com/en-us/powershell/module/storage/get-volume
- https://learn.microsoft.com/en-us/windows-server/administration/windows-commands/robocopy
