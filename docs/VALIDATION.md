# Validação

Ambiente de desenvolvimento: Linux, sem `pwsh`, Windows PowerShell ou Robocopy. Os testes Pester foram escritos, mas NÃO executados aqui. CI preparada para Windows PowerShell 5.1. Não declarar pronto para formatação antes de executar os testes e validar backup/restauração no computador real.

Verificações estáticas locais: sintaxe JSON da configuração; existência dos arquivos requeridos; primeiro comando `cd`; ausência de switches de purga no motor; presença de SHA-256, lock, staging e retenção. Essas verificações não validam sintaxe/semântica PowerShell nem substituem integração Windows.

Casos ainda necessários: interrupção durante cópia, erro de disco/espaço, arquivo bloqueado, UNC, exFAT/NTFS, nomes Unicode e longos, OneDrive, junctions, arquivos alterados durante cópia e rollback. Falhas devem preservar o destino anterior. A referência extensa ainda precisa de revisão completa independente.
