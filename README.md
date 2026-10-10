# Backup de dados do Windows — dados primeiro

Projeto de auditoria e backup para **Windows 10/11, PowerShell 5.1 e HD/SSD externo USB em NTFS**. Protege documentos, fotos, vídeos, projetos, notebooks e código-fonte sem tentar fazer uma imagem do Windows.

**Novidade:** a descoberta automática não varre mais `C:\` ou outros discos inteiros. Ela escolhe pastas pessoais conhecidas e pastas de trabalho encontradas **apenas no primeiro nível** do perfil e dos discos internos. Pastas de programas, caches e o restante de `AppData` não entram automaticamente. Isso reduz o escopo e evita milhares de arquivos irrelevantes, **mas exige que você revise o que ficou de fora**.

## Como usar

1. Baixe o ZIP pelo botão **Code → Download ZIP** deste repositório e extraia-o. Ou clone com Git.
2. Abra **`Iniciar.cmd`** (sem executar como administrador, salvo necessidade justificada).
3. Escolha **1 — Ver plano de pastas**. É rápido, não usa o HD externo, não lê conteúdo nem calcula hashes. Confira a lista e as indicações `REVIEW_REQUIRED`.
4. Se faltou alguma pasta importante, escolha **4 — Selecionar minhas pastas manualmente** e depois use as opções **5 e 6** para auditar/copiar *essas pastas*. O modo manual é independente do automático; não combina automaticamente as duas listas.
5. Conecte o HD/SSD USB NTFS e escolha **2 — Auditar** para comparar os dados selecionados com o backup existente. Escolha o destino correto. **Auditoria não copia arquivos.**
6. Confira o relatório `LEIA-ME.html` no HD. Se estiver correto, escolha **3 — Fazer backup**, usando **a mesma pasta de destino**. Confira o relatório novo.
7. Teste a restauração: copie um documento, uma foto e um projeto do HD para outra pasta e abra-os.

| Status | Significado |
|---|---|
| `NEEDS_COPY` | Ainda não há cópia confirmada; **não foi copiado** |
| `VERIFIED` | Arquivo copiado e verificado por SHA-256 |
| `SKIP_IDENTICAL` | Já havia cópia com conteúdo conferido |
| `REUSED_EXISTING` | Conteúdo igual encontrado em outro caminho do destino |
| `ERROR` | Falha ou leitura incompleta: requer revisão |

### O que a descoberta automática inclui?

- Documentos, Área de Trabalho, Downloads, Imagens, Música, Vídeos e caminhos conhecidos redirecionados; OneDrive quando identificado.
- Pastas de trabalho com nomes reconhecidos (por exemplo `Projetos`, `Projects`, `Code`, `GitHub`, `Dados`, `Notebooks`) **somente no primeiro nível** do perfil e dos volumes internos.
- Alguns diretórios de configuração pessoal (`.ssh`, `.gnupg`, `.jupyter`, `.ipython`) no primeiro nível do perfil. **Proteja e criptografe a mídia** quando guardar chaves ou documentos sensíveis.

**Não é uma busca universal por arquivos pessoais.** Projetos em pastas com nomes diferentes, arquivos soltos em `C:\`, dados de programas (Outlook, Thunderbird, Zotero, navegadores, WSL, Docker, bancos, VMs) e volumes sem letra podem ficar fora. Consulte [cobertura e exportações especiais](docs/COVERAGE.md) e inclua dados necessários manualmente. Dados em nuvem precisam estar disponíveis localmente.

### Como funciona a auditoria hierárquica?

```text
Discos internos (somente diretórios de primeiro nível)
    ├── pastas de dados reconhecidas → arquivos relevantes
    │     ├── projeto → código, notebooks, manifests e documentos
    │     └── dependências identificadas → adiadas no modo automático
    └── Windows, Program Files, caches de software → não selecionados
```

A etapa **1** só descobre e apresenta raízes, sem examinar os arquivos. A auditoria **2** ainda calcula SHA-256 dos arquivos das pastas selecionadas, porque precisa verificar conteúdo. A cópia **3** usa staging e conferência de hashes. A indexação do destino começa por tamanhos para evitar ler classes de arquivos sem candidatos.

O manifesto **Merkle** compara inventários observados entre execuções, mas **não** dispensa ler arquivos para detectar mudanças. **MinHash/LSH** e Jaccard aparecem no mapa visual opcional (opção **8**, Python 3.9+) para sugerir pastas parecidas; não decidem o que excluir nem substituem SHA-256. [Detalhes técnicos e limites](docs/INCREMENTAL.md).

## Se a energia acabar

A execução interrompida **não significa backup completo**. Consulte `ANDAMENTO.html` e os CSVs parciais apenas para diagnóstico; o relatório final de uma nova execução é o que deve ser revisado. Execute novamente, escolha o **mesmo destino** e não desconecte a mídia. Cópias previamente confirmadas podem ser reutilizadas após nova verificação, mas **não há retomada do ponto exato de um arquivo interrompido**.

O programa não apaga arquivos de origem, não usa `/MIR` nem formata discos. Só aceita destinos externos elegíveis e impede raízes sobrepostas. Arquivos em uso, links/redirecionamentos, arquivos não disponíveis na nuvem e mudanças concorrentes podem causar erros. **Não formate o computador com base apenas em um relatório de sucesso**: revise a cobertura, mantenha uma segunda cópia e teste restaurações.

## Comandos opcionais

```powershell
# Ver escopo em segundos (sem USB)
powershell.exe -NoProfile -STA -File .\Backup.ps1 -Mode Plan -AutoDiscover

# Comparar os dados selecionados
powershell.exe -NoProfile -STA -File .\Backup.ps1 -Mode Audit -AutoDiscover -SelectDestination -OpenReport

# Copiar e verificar depois de revisar
powershell.exe -NoProfile -STA -File .\Backup.ps1 -Mode Backup -AutoDiscover -SelectDestination -OpenReport
```

A configuração manual usa `backup.local.json` (nunca publique esse arquivo). O modo automático não substitui a configuração manual nem combina suas origens.

## Desenvolvimento e documentação

- [Cobertura e dados especiais](docs/COVERAGE.md)
- [Segurança, interrupções e limitações](docs/SAFETY.md)
- [Merkle, MinHash e métricas](docs/INCREMENTAL.md)
- [Validação](docs/VALIDATION.md)
- [Organização visual opcional](docs/ORGANIZATION.md)

Testes de desenvolvimento: `Invoke-Pester .\tests -Output Detailed` (Pester 5.7.1, Windows). O projeto **não** oferece VSS, backup transacional, restauração automática ou proteção de bancos em uso; para esses casos, faça exportações nativas e teste a recuperação.

Licença MIT.
