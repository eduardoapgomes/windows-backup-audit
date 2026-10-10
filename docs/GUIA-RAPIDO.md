# Guia rápido: faça seu backup com segurança

**Para Windows 10/11.** Este guia é para quem quer proteger documentos, fotos e projetos sem aprender comandos nem os nomes dos algoritmos.

> **Ordem recomendada: conferir → copiar → testar a recuperação.** A auditoria não copia seus arquivos. O backup só começa quando você escolhe a opção de cópia.

## Antes de começar

- Conecte um **HD ou SSD externo USB, formatado em NTFS**, com espaço suficiente. O programa não formata discos.
- Feche documentos e programas que estejam modificando arquivos. Para bancos de dados, máquinas virtuais e ambientes especiais, faça também a exportação própria do aplicativo.
- Baixe o projeto pelo botão **Code → Download ZIP** em https://github.com/eduardoapgomes/windows-backup-audit e extraia-o, **ou** use Git conforme as instruções do [README](../README.md).
- Abra a pasta extraída e dê dois cliques em **Iniciar.cmd**. Não é preciso instalar Python nem editar JSON para usar as opções automáticas.

## Passo 1 — Conferir o que será protegido

No menu, escolha **1 — Auditoria automática**. O programa seleciona **pastas pessoais e pastas de dados/projetos conhecidas**, sem percorrer `C:\`, `C:\Users` ou pastas de instalação de software por inteiro. Depois, pede que você selecione o **HD USB** e uma **pasta de destino**.

- Se já existem backups manuais ou parciais, escolha a pasta que **contém** essas cópias.
- Se vai começar do zero, escolha a raiz do HD USB; o programa criará sua pasta própria.
- Aguarde a execução terminar. A página **ANDAMENTO.html** mostra o progresso; ela não confirma sucesso enquanto o processo está rodando.

**A auditoria não copia arquivos de origem.** Ela grava relatórios no USB. Na auditoria automática rápida, arquivos sem candidatos do mesmo tamanho no destino são registrados como `NEEDS_COPY` sem leitura integral de SHA-256; arquivos comparáveis são verificados por hash. Isso acelera a primeira execução. A opção avançada `-FullAudit` lê todos os arquivos selecionados.

## Passo 2 — Ler o resultado

Abra **LEIA-ME.html** na pasta de relatório indicada pelo programa (`_RELATORIOS`). Verifique as pastas `INCLUDED`, os locais `REVIEW` (não examinados), arquivos esperados, exclusões e erros. Pastas de nome incomum e arquivos soltos nas raízes dos discos exigem inclusão manual.

| Mensagem | O que significa |
|---|---|
| `NEEDS_COPY` | Ainda precisa de uma cópia; na auditoria rápida, SHA-256 pode estar vazio |
| `SKIP_IDENTICAL` | Já existe cópia igual, conferida |
| `REUSED_EXISTING` | Cópia igual localizada em outro caminho do destino |
| `VERIFIED` | Arquivo copiado e conferido no modo Backup |
| `ERROR` | Houve falha; leia o detalhe e corrija |
| `REVIEW` em `cobertura.csv` | Local não examinado pelo modo automático; inclua manualmente se houver dados importantes |

**Se aparecer erro, `REVIEW`, falta de cobertura ou dependência excluída, não considere esses dados protegidos.** Confira também `cobertura.csv` e, quando houver, `falhas-enumeracao.csv` e `dependencias.csv`. A ausência de erros não prova que todo o computador foi incluído.

## Passo 3 — Fazer o backup

Depois de revisar a auditoria, volte a **Iniciar.cmd** e escolha **2 — Backup automático**.

1. Selecione o **mesmo HD USB e a mesma pasta** usados na auditoria.
2. Aguarde o fim; não desconecte o disco.
3. Abra o **novo LEIA-ME.html**. Confira `VERIFIED`, `SKIP_IDENTICAL`, `REUSED_EXISTING` e qualquer `ERROR`.

O programa só reutiliza uma cópia após verificar seu conteúdo. Ele preserva versões anteriores quando substitui um arquivo alterado e **não apaga arquivos da origem**. Uma nova execução pode ser feita para conferir e atualizar os dados.

## Passo 4 — Testar a recuperação

Abra `inventario.csv` do backup. A coluna **Destination** mostra onde está a cópia real, inclusive quando aparece `REUSED_EXISTING`.

Copie **alguns arquivos do HD USB para uma pasta vazia** fora das origens: um documento, uma foto e um projeto. Abra-os nos aplicativos habituais e, quando possível, compare os hashes SHA-256 com o inventário. Guarde os relatórios com o backup.

**Não formate nem reinstale o Windows apenas porque o programa terminou sem erros.** Antes disso, revise a cobertura, resolva pendências, teste a restauração e mantenha uma segunda cópia independente.

## Dúvidas comuns

**O HD não aparece para seleção?** Ele precisa ser reconhecido como USB externo/NTFS, gravável e estar em disco físico diferente das origens. Se o Windows não confirmar a identidade, o programa bloqueia o destino por segurança. Não tente contornar essa verificação.

**Um arquivo do OneDrive não está disponível?** No Explorador, escolha **Sempre manter neste dispositivo**, aguarde o download e execute novamente. Arquivos apenas na nuvem não são confirmados como protegidos.

**Tenho arquivos em uma pasta diferente (ou soltos em C:\\).** Use as opções **3, 4 e 5** do menu: configurar, auditar e copiar no modo manual. O modo automático é deliberadamente limitado a pastas de dados reconhecidas; não varre o disco inteiro.

**A energia acabou no meio da execução.** `ANDAMENTO.html` e arquivos CSV parciais **não confirmam um backup completo**. Não apague pastas temporárias ou versões antigas sem revisão. Confira o que já existe no USB, execute uma nova auditoria e depois o backup no mesmo destino. Arquivos reutilizados são novamente comparados por SHA-256.

**Por que não examinou `node_modules` ou caches?** O padrão evita bibliotecas Node/Python reconhecidas e caches regeneráveis. Se você modificou código dentro dessas pastas, use a opção avançada `-DependencyPolicy Include` e confira o espaço disponível.

**E se houver arquivos repetidos?** O programa verifica hashes SHA-256 e pode reutilizar uma cópia existente; não remove duplicatas antigas. Não mova nem apague arquivos reutilizados sem considerar o `inventario.csv`.

**Preciso entender Merkle ou MinHash?** Não. O backup gera automaticamente os relatórios de comparação **Merkle**. Na auditoria rápida, folhas sem SHA ficam explicitamente não verificadas. **MinHash** aparece apenas no mapa visual opcional da opção **8**, que exige Python 3.9+ e sugere pastas parecidas sem mover ou excluir arquivos. Esses recursos não dispensam a verificação do backup.

**Como atualizar o projeto?** Se você usou Git, feche qualquer execução e, na pasta do projeto, rode `git pull --ff-only`. Se baixou ZIP, baixe uma versão nova sem sobrescrever sua configuração manual `backup.local.json`.

## Mais detalhes

- [README completo e instalação](../README.md)
- [O que Merkle e MinHash realmente fazem](INCREMENTAL.md)
- [Cobertura e dados especiais](COVERAGE.md)
- [Segurança e limites](SAFETY.md)
- [Validação antes de usar em dados importantes](VALIDATION.md)

Este programa **não cria imagem do Windows nem snapshots VSS**, não restaura automaticamente e não garante consistência de arquivos de aplicativos em uso.