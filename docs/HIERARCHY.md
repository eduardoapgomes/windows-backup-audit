# Decisões hierárquicas e análise de semelhança

## Implementado: dados essenciais primeiro

A política padrão é `-DependencyPolicy Auto`:

1. A auditoria identifica diretórios de bibliotecas por estrutura e marcadores, registra a decisão e não enumera seu conteúdo.
2. Código próprio, notebooks, documentos, dados, `.git`, manifests/lockfiles, `pyvenv.cfg` e `conda-meta` continuam no fluxo normal. Não excluímos uma pasta inteira por se chamar `venv`, `env`, `Lib` ou `anaconda3`.
3. O índice inicial do HD também adia bibliotecas reconhecidas. Esse recorte é documentado em `indice-excluido.csv`; conteúdo dentro dessas pastas não participa da comparação essencial inicial.
4. No modo Backup, as bibliotecas são processadas depois das origens essenciais, somente se não houver erros de leitura/enumeração anteriores. Antes de cada pasta opcional, mede-se seu tamanho lógico por enumeração de metadados e exige-se esse tamanho mais 256 MiB livres. É uma condição conservadora: não prevê exatamente espaço adicional nem reserva espaço contra outros processos.
5. Se faltar espaço, a pasta opcional recebe `NOT_COPIED_SPACE`. Não se apaga nenhuma cópia para abrir espaço. Se houver erro essencial/anterior, recebe `NOT_COPIED_ESSENTIAL_OR_PREVIOUS_ERRORS`. Copiar bibliotecas não tem prioridade sobre resolver dados essenciais.
6. Quando há espaço, reabre-se o índice das bibliotecas do destino e reutiliza-se conteúdo idêntico. Cópias opcionais continuam verificadas por SHA-256, com os mesmos controles físicos e de staging.

`-DependencyPolicy Exclude` omite bibliotecas tanto da auditoria quanto do backup. `-DependencyPolicy Include` volta ao exame completo e pode demorar. São opções explícitas no ponto de entrada Backup.ps1; Auto vale também no menu.

### Reconhecimento conservador

- Node: diretório `node_modules` com `package.json` no pai ou `.package-lock.json` na própria pasta.
- Python no Windows: `Lib\site-packages` cujo ambiente contém `pyvenv.cfg`, `conda-meta\history`, ou a combinação `Scripts\activate.bat` e `Scripts\python.exe`.
- Sem marcador suficiente, o conteúdo continua sendo examinado.
- Links/junctions permanecem bloqueados antes de aplicar a política. Não executamos Python/npm/Conda encontrados para identificar ambientes.

Esses marcadores identificam a função habitual da pasta, não provam que todos os seus arquivos sejam descartáveis. Alterações locais feitas dentro de bibliotecas, pacotes privados/locais ou versões indisponíveis podem não ser recuperáveis por reinstalação. Use Include nesses casos. Preservar receitas e lockfiles ajuda, mas não garante reconstrução bit a bit. O programa não gera automaticamente um environment.yml nem promete transportar um ambiente virtual funcional.

## Relatórios e retomada

`dependencias.csv` registra pasta, evidência, decisão, raiz proprietária e tamanho estimado quando medido. Tamanho vazio significa **não medido**, nunca zero. Pastas adiadas/excluídas não contam como protegidas. `inventario.csv` identifica ESSENTIAL ou OPTIONAL_DEPENDENCY em Priority. O HTML apresenta as decisões de bibliotecas separadamente.

Falhas de enumeração e decisões são persistidas no acompanhamento parcial. Isso melhora a observabilidade, mas ainda não implementa retomada transacional: uma nova execução revalida o conteúdo. Não atualize o código no meio de uma execução; termine ou interrompa conscientemente antes de usar a versão nova.

## Experimento separado: agrupamento sem modificar arquivos

O utilitário opcional `tools/analyze_hierarchy.py` usa Python 3 e somente a biblioteca padrão. Python não é dependência do backup. Ele lê um inventário já existente e não abre origens nem destinos descritos nele.

```powershell
python .\tools\analyze_hierarchy.py "D:\pasta-do-relatorio\inventario.csv" --output "$env:TEMP\analise-hierarquia-nova"
```

Para comparar também a NCD experimental:

```powershell
python .\tools\analyze_hierarchy.py "D:\pasta-do-relatorio\inventario.csv" --ncd --output "$env:TEMP\analise-hierarquia-ncd-nova"
```

A saída deve ser uma pasta nova. O utilitário cria hierarquia.html e hierarquia.json; eles são relatórios privados, não devem ser publicados no GitHub. Nenhum caminho listado no inventário é usado para mover, excluir ou executar arquivos.

- Constrói a hierarquia observada e colapsa `node_modules`/`site-packages` para a análise. Esse filtro lexical experimental não substitui a política conservadora do backup.
- Reconhece unidades de projeto quando o inventário contém `.git` ou `node_modules`. Não propõe separar arquivos internos dessas unidades. Sem esses sinais, não há garantia de identificar todo projeto.
- Jaccard compara conjuntos de caminhos relativos. No máximo 64 unidades são comparadas, até 2.016 pares, e no máximo 30 candidatos com ao menos dois nomes em comum são apresentados. Ancestrais/descendentes são relações hierárquicas já conhecidas e não são tratados como novas sugestões.
- NCD opcional compara apenas os manifests de caminhos desses candidatos: zlib nível 6, mínimo entre C(xy) e C(yx), amostras de até 16 KiB por unidade. Truncamentos são indicados no JSON. NCD = (C(xy) - min(C(x),C(y))) / max(C(x),C(y)). É uma variante prática simetrizada, não uma distância semântica validada.
- Um fingerprint SHA-256 ordenado representa nomes relativos, tamanhos e hashes **observados**. Não é uma árvore de Merkle persistente nem prova que uma pasta foi inteiramente examinada. O arquivo parcial não fornece essa evidência.
- A tabela hierárquica contém totais com descendentes: não somar a contagem de um pai com a de seus filhos.

Mesmo com Jaccard igual a 1, duas pastas podem conter resultados diferentes sob os mesmos nomes. Semelhança nunca dispensa uma cópia, autoriza exclusão ou prova igualdade. A saída não é uma organização ótima dos documentos nem agrupa por assunto real. Essa etapa exige dados de conteúdo, avaliação humana e testes independentes.

## Métodos que fazem sentido para as próximas etapas

1. Metadados para selecionar candidatos: tamanhos diferentes descartam igualdade; tamanho/data iguais não confirmam igualdade.
2. SHA-256 para confirmação exata de conteúdo antes de reutilizar uma cópia. Um hash calculado durante leitura não garante consistência de bancos ativos nem de todo um conjunto de arquivos.
3. Manifestos persistentes e árvore de Merkle para representar a hierarquia em snapshots. A primeira captura lê conteúdo; snapshots posteriores precisam detectar mudanças com segurança. Nome, tamanho e timestamp sozinhos não são prova de conteúdo inalterado.
4. Jaccard como base interpretável de semelhança estrutural. MinHash/LSH pode reduzir a seleção de candidatos em grandes coleções, com possíveis falsos negativos; somente análise, nunca regra de exclusão de backup.
5. Extração de texto e representações semânticas podem ser avaliadas futuramente para assunto. Projetos devem continuar como unidades, com sugestões revisáveis e reversíveis.
6. Compactação opcional só depois de assegurar dados essenciais. Gerar um arquivo compactado também lê seus membros; SHA-256 do arquivo resultante não prova sozinho que a fonte inteira foi incluída. Seriam necessários manifesto, verificação por extração, registro do compressor, parâmetros e formato determinístico para comparar arquivos compactados. Essa modalidade **não está implementada**.

NCD não é atalho para igualdade nem substitui uma verificação de integridade. Comparação indiscriminada de todos os pares cresce quadraticamente, e compressor/janela/representação influenciam os resultados. Por isso ela está fora do caminho crítico do backup.

## Referências primárias consultadas

- Python venv — ambientes descartáveis/recriáveis e limitações de portabilidade: https://docs.python.org/3/library/venv.html
- npm ci — restauração guiada por lockfile: https://docs.npmjs.com/cli/commands/npm-ci/
- Conda — exportação e reconstrução de ambientes: https://docs.conda.io/projects/conda/en/stable/user-guide/tasks/manage-environments.html
- Cilibrasi e Vitányi, Clustering by compression: https://arxiv.org/abs/cs/0312044
- Large Language Models and Normalized Compression Distance: Better Compression Yet Worse Accuracy (2026): https://doi.org/10.3233/FAIA251322
- Estruturas de árvore e identificação por conteúdo em sistemas de backup: https://restic.readthedocs.io/en/v0.5.0/Design/

## Atualização: Merkle e MinHash

O experimento acima mantém seu fingerprint simples. O mecanismo de backup agora grava manifestos Merkle separados e o painel contextual usa MinHash/LSH para selecionar pares. Consulte [deduplicação e comparação incremental](INCREMENTAL.md) para distinguir os recursos implementados dos limites de detecção de mudanças.
