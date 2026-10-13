# Mudanças

## 2.0.0 — versão simplificada

Reescrita do motor com base no relatório de análise do projeto: menos conceitos para o usuário, backup incremental de verdade e o mesmo cuidado com segurança.

### Novo

- **Configuração em texto simples** (`configuracao.txt`): origens, HD de destino e exclusões, editável no Bloco de Notas. O assistente sugere as pastas pessoais e de projetos e importa o `backup.local.json` da versão 1.
- **Incremental por manifesto**: tamanho, data e SHA-256 de cada arquivo conferido. O que não mudou não é lido de novo. O manifesto tem checksum próprio, é gravado de forma atômica e salvo a cada minuto (retomada após queda de energia).
- **Robocopy multithread por pasta** (`/MT:8`), copiando só arquivos ausentes no HD (`/XC /XN /XO`): ele nunca sobrescreve.
- **Versões anteriores**: arquivo alterado tem a cópia antiga movida para `_VERSOES_ANTERIORES\<data>\`.
- **Pasta renomeada ou movida** é movida no HD em vez de copiada de novo (conferida por SHA-256).
- **Verificar integridade**: relê o HD e confere cada arquivo com o manifesto (também por amostragem, `-Amostra`); cópias com problema são refeitas no backup seguinte.
- **Simular**: mostra o que será feito sem gravar nada.
- **Agendamento** no Agendador de Tarefas, sem administrador, com aviso na tela se o HD não estiver conectado.
- **HD com letra trocada** é encontrado automaticamente; rodízio de dois HDs suportado.
- **Motor nativo em C#**: listagem com `FindFirstFileExW`, caminhos com mais de 260 caracteres, SHA-256 pela CNG do Windows, leitura da origem e do HD em paralelo.
- **Relatório único** (`RELATORIO.html`) com resultado em uma frase, mais `detalhes.tsv` (Excel) e `resumo.json`.
- **Códigos de saída** claros: 0, 1 (avisos), 2 (erros), 3 (não executado).
- Testes de ponta a ponta com Robocopy real no Windows PowerShell 5.1 e no PowerShell 7; medição de desempenho contra a versão 1 no CI.

### Removido

- Auditoria sem cópia (substituída por **Simular**, que é mais rápida e mostra o plano real).
- Descoberta automática a cada execução (agora a configuração é sugerida uma vez e fica visível e editável).
- Mapa visual em Python, MinHash/LSH, Jaccard e manifesto Merkle: ajudavam a organizar pastas, não a proteger os dados. Continuam no histórico (commit `46dad4d`).
- Reaproveitamento de conteúdo em outro caminho do HD (`REUSED_EXISTING`): o backup passa a ser um espelho simples das pastas, que se restaura com o Explorador.
- Política de dependências com detecção de `pyvenv.cfg`/`package.json`: substituída por exclusões configuráveis por nome.

### Compatibilidade

- O HD da versão 1 é aproveitado: pastas `AUTO_…` são renomeadas e os arquivos existentes são conferidos, não recopiados. Detalhes em [docs/ATUALIZAR.md](docs/ATUALIZAR.md).
- Parâmetros antigos do `Backup.ps1` (`-Mode`, `-AutoDiscover`, `-FullAudit`, `-DependencyPolicy`) foram substituídos por `-Acao`.
- As mesmas regras de destino continuam: HD USB, NTFS, outro disco físico, sem sistema.
