# Mapa visual e catálogo por contexto

O objetivo é encontrar dados espalhados sem comprometer o backup. A cópia conserva seus caminhos lógicos e a verificação SHA-256. Sobre esse inventário, o painel oferece uma organização virtual: a mesma pasta/projeto pode ser relacionada a arquivos soltos sem ser desmembrada ou movida.

## Abrir sem editar configuração

1. Instale Python 3.9 ou superior pelo instalador oficial: https://www.python.org/downloads/windows/ (se já usa Python/Anaconda, pode usar seu terminal com Python disponível). Nenhum pacote pip é necessário.
2. Atualize o projeto e abra `Iniciar.cmd`.
3. Escolha **8 — Mapa visual e agrupamentos**.
4. Selecione `inventario.csv` da execução desejada. Ele fica na pasta de relatórios indicada pelo backup. Pode estar ainda em produção: nesse caso tudo é parcial.
5. O navegador abre o painel local. A janela permanece acompanhando o CSV a cada 30 segundos; Ctrl+C encerra somente esse acompanhamento. A auditoria/backup em outra janela continua.

A opção 8 exige Python; as opções de auditoria/backup continuam independentes dele. O painel não lê os conteúdos apontados pelas colunas Source/Destination, não acessa a internet e não modifica esse CSV. O catálogo é criado numa pasta temporária exclusiva; guarde a pasta inteira se quiser preservá-lo. Ele não passa a integrar automaticamente seu backup.

## O que aparece

- **Hierarquia navegável:** entre nas pastas, volte ao pai e veja os descendentes. Totais incluem filhos; somá-los aos pais duplica contagens.
- **Gráficos de tamanho:** até 20 subpastas por nível; as demais continuam na navegação.
- **Cobertura:** confirmações registradas no inventário, pendências e erros. Não há nova validação física do HD no painel. Bibliotecas adiadas e pastas não enumeradas não aparecem como protegidas.
- **Busca:** origem, situação e destino, com 100 arquivos por página. Caminho planejado não é cópia confirmada.
- **Relações:** até seis ligações ilustrativas por filtro e até 200 sugestões na tabela; exportação CSV contém todas as sugestões calculadas.

## Como os contextos são sugeridos

Marcadores observados `.git`, `node_modules`, `pyproject.toml`, `package.json`, `Cargo.toml`, `go.mod`, `pom.xml` e `.sln` ajudam a reconhecer projetos. Não se executa código desses projetos. A raiz identificada mais próxima contém seus arquivos como uma unidade. Projetos sem marcadores no inventário podem não ser reconhecidos.

Nesta versão, “solto” significa arquivo diretamente em Downloads, Download, Desktop ou Área de Trabalho, fora de um projeto reconhecido. Subpastas dessas áreas são possíveis contextos; documentos já dentro delas não são tratados como soltos automaticamente. Isso evita desmontar estruturas existentes.

Um índice invertido relaciona termos dos nomes dos arquivos e das pastas. Exige pelo menos dois termos compartilhados, ou SHA-256 válido já observado igual. São excluídos termos genéricos e conteúdo interno de bibliotecas. O índice limita candidatos (300 por arquivo); termos presentes em mais de 96 grupos não expandem a busca. Há até 3 resultados por arquivo. Isso evita comparar todos os arquivos entre si, mas pode deixar relações de fora.

O índice apresentado é Jaccard dos termos utilizados, ou 1 para hash observado igual. **Não é probabilidade de acerto nem compreensão semântica do documento.** Uma diferença inferior a 0,05 entre os dois primeiros candidatos é marcada AMBIGUO; esse limiar é heurístico. EVIDENCIA_FRACA indica que os termos compartilhados aparecem somente em nomes de arquivos, sem apoio no nome da pasta nem hash igual; nomes pessoais podem criar essas coincidências. SEM_EVIDENCIA conserva explicitamente a ausência de conclusão. REVISAR_SUGESTAO também exige revisão humana. Igualdade de hash observada não prova que um arquivo pertence ao assunto da pasta.

A avaliação é sobre o CSV, sem extração de texto de PDF/Office, embeddings ou chamadas de IA. Contextos verdadeiros precisam de validação do usuário. Nenhuma sugestão é usada para excluir, mover, renomear ou omitir cópias.

## Terminal (opcional)

Gerar uma vez em uma **nova** pasta, que não pode existir:

```powershell
python .\tools\organize_inventory.py "D:\CAMINHO_DO_RELATORIO\inventario.csv" --output "$env:USERPROFILE\Desktop\Mapa-backup-novo" --open
```

Acompanhar sem especificar pasta de saída (usa uma pasta temporária exclusiva):

```powershell
powershell.exe -NoProfile -STA -File .\Organizar.ps1 -Watch
```

Saídas: `painel.html`, `catalogo.json` e `sugestoes.csv`. Abra o HTML offline; os links relativos exigem manter os três juntos. A atualização do navegador a cada 30 segundos preserva a pasta e os textos de busca quando o armazenamento local está disponível; posição de rolagem/página pode reiniciar. O JSON/CSV completos podem ser maiores que as visualizações limitadas.

## Desempenho e limites

A agregação lê linhas do inventário e percorre ancestrais de cada caminho; mantém o catálogo em memória. A comparação contextual usa candidatos indexados e limitados. Em acompanhamento, o CSV é reprocessado somente quando tamanho ou data de modificação mudam. Ainda não existe atualização incremental por linha nem paginação no servidor: inventários com milhões de arquivos exigirão banco de dados e interface adicional.

Esses metadados servem apenas para atualizar a visualização. **Não são usados para dispensar SHA-256 no backup.** O painel não implementa cache Merkle, MinHash, compressão ou cópia física reorganizada. Ler uma primeira cópia para verificá-la continua necessário.

Linhas inválidas/incompletas durante escrita concorrente são contabilizadas como rejeitadas. Um CSV truncado mas sintaticamente válido pode parecer um inventário menor: o painel nunca declara cobertura completa. Consulte os relatórios da execução para conclusão, falhas e exclusões. Os dados e agrupamentos permanecem privados no computador; não compartilhe os relatórios sem revisão.
