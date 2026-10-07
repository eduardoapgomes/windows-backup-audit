# Validação

Ambiente de desenvolvimento: Linux, sem `pwsh`, Windows PowerShell ou Robocopy. Os 5 testes Pester passaram no GitHub Actions em Windows Server 2025, Windows PowerShell 5.1, com Robocopy real: 5 aprovados, 0 falhas e 0 ignorados. Execução de 07/10/2026: https://github.com/eduardoapgomes/windows-backup-audit/actions/runs/37632591828 . Commit testado: c52f885c0c26ff331cc1420e61820d10e2552579. Isso não substitui validar backup/restauração no computador e mídia reais.

Verificações estáticas locais: sintaxe JSON da configuração; existência dos arquivos requeridos; primeiro comando `cd`; ausência de switches de purga no motor; presença de SHA-256, lock, staging e retenção. Essas verificações não validam sintaxe/semântica PowerShell nem substituem integração Windows.

Casos ainda necessários: interrupção durante cópia, erro de disco/espaço, arquivo bloqueado, UNC, exFAT/NTFS, nomes Unicode e longos, OneDrive, junctions, arquivos alterados durante cópia e rollback. Falhas devem preservar o destino anterior. A referência extensa ainda precisa de revisão completa independente.
