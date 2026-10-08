# Deduplicação por tamanho, Merkle e MinHash

## O que está implementado

| Técnica | Uso real | O que não autoriza |
|---|---|---|
| Política top-down | Adia bibliotecas reconhecidas; prioriza dados essenciais | Descartar uma pasta apenas porque seu nome parece irrelevante |
| Índice por tamanho | Enumera o destino sem ler todo o conteúdo; só calcula hashes nos grupos de tamanho solicitados por origens | Ignorar arquivos pequenos ou únicos no backup |
| SHA-256 em blocos | Verifica origens, cópias e candidatos reutilizados | Tratar metadados ou similaridade como identidade |
| Merkle persistente | Grava `merkle.json`, checksum e diferenças entre inventários; comparação para na raiz de uma subárvore igual | Pular leitura de uma origem porque o manifesto antigo não mudou |
| MinHash + LSH | Seleciona pares candidatos entre pastas; Jaccard confirma semelhança de nomes nos conjuntos analisados | Mover, apagar ou omitir cópias por semelhança |

## Filtro por tamanho: economia efetiva de leitura no HD

O índice inicial enumera nomes e tamanhos no destino. Ao comparar uma origem, apenas a classe de mesmo tamanho é lida para construir seu índice SHA-256. Classes nunca solicitadas permanecem sem leitura de conteúdo. Quando uma classe é resolvida, o índice permanece em memória naquela execução; o candidato escolhido é **rehashado antes de reutilizar**. Cópias novas verificadas entram no índice.

Todas as origens elegíveis continuam recebendo hash, inclusive arquivos vazios, pequenos e de tamanho único. Deduplicação e integridade são finalidades diferentes. Um documento único não é descartável, e um tamanho único não prova que sua cópia foi feita corretamente. Não há corte de 64 MB nem exclusão automática por extensão.

Esse índice pode ainda ser caro se muitos arquivos tiverem o mesmo tamanho. Alterações externas durante a execução podem gerar falhas ou perder oportunidades de deduplicação; nenhuma decisão usa um hash antigo sem revalidar o candidato selecionado. O sistema não é snapshot transacional.

## Manifesto Merkle de cada execução

Depois do processamento, tanto Audit quanto Backup escrevem, na própria pasta de relatórios:

- `merkle.json`: árvores das raízes configuradas, nomes relativos, tamanhos, hashes observados, situação e destino registrados.
- `merkle.sha256`: checksum dos bytes do manifesto para detectar alteração acidental. Não é assinatura autenticada.
- `merkle-delta.csv`: comparação com o manifesto disponível da execução anterior mais recente, quando existir.
- `metricas.json`: leituras SHA concluídas, bytes correspondentes, tempo gasto em hashes, arquivos enumerados no destino, candidatos lidos por tamanho, classes resolvidas e duração.

Cada folha combina tipo, tamanho e SHA-256. Cada diretório combina nomes dos filhos, ordenados ordinalmente, e seus hashes. A codificação usa componentes UTF-8 prefixados pelo comprimento em bytes (`tamanho:conteúdo`), evitando ambiguidades de concatenação. A raiz virtual é `@`. O formato é `windows-backup-merkle-v1`.

**ContentRoot descreve conteúdo observado, não prova proteção nem cobertura completa.** Status de cópia e Destination são metadados separados, cobertos pelo checksum do arquivo de manifesto. Conteúdo não lido vira UNREAD e invalida a confirmação de hashes daquela subárvore. Pastas vazias, arquivos não enumerados, exclusões, falhas de acesso e bibliotecas adiadas exigem consultar cobertura e decisões. `CoverageComplete` permanece explicitamente falso.

A comparação testa hashes de diretório e encerra a descida quando uma subárvore observada é igual e tem hashes válidos. Mudanças de escopo ou política geram SCOPE_CHANGED. Um item ausente do inventário atual vira NOT_OBSERVED_NOW, sem concluir que foi apagado. Um checksum anterior inválido gera BASELINE_INVALID; o manifesto antigo nunca governa a cópia.

### O que “incremental” significa aqui

O backup já reaproveita conteúdo confirmado e copia apenas o necessário. Agora os manifestos permitem comparação hierárquica entre execuções, e o índice de destino evita leituras de classes de tamanho irrelevantes. **Não há cache que dispense a releitura de origens baseado somente em nome, tamanho ou data.** O snapshot atual precisa de hashes atuais; depois disso, a comparação dos manifestos pode pular subárvores iguais.

Para eliminar essas releituras com garantias maiores, seria necessário integrar e validar uma fonte confiável de mudanças (por exemplo, journal NTFS com identidade, continuidade e fallback integral) e/ou snapshots. Isso não foi implementado. Merkle sozinho não detecta uma mudança que ninguém observou.

## MinHash/LSH no mapa visual

A opção 8 do `Iniciar.cmd` gera também relações estruturais entre pastas, visíveis na seção 5 do painel. A seção 6 mostra o root observado e métricas da execução, quando os arquivos já existirem.

- Representação: conjunto de nomes relativos dos arquivos observados por grupo; bibliotecas e internos `.git` não entram nas sugestões.
- Assinatura: 64 componentes determinísticos, família afim módulo `2^61-1`, sobre SHA-256 dos nomes; seed fixa e esquema versionado.
- LSH: 16 bandas de 4 componentes; ao menos uma banda igual seleciona um candidato.
- Revisão exata: Jaccard nos conjuntos de nomes analisados, pelo menos dois nomes em comum e coeficiente >= 0,5.
- Limites: até 5.000 grupos, 4.096 nomes por grupo, buckets com no máximo 64 grupos, 50.000 pares candidatos e 500 relações apresentadas. Truncamentos/saturações ficam nos dados do catálogo. Grupos com menos de dois nomes não são comparados.
- Cache: assinaturas podem ser reutilizadas quando o fingerprint dos nomes observados coincide. Isso acelera a análise do catálogo, nunca a verificação de cópias.

LSH pode perder relações; limites também reduzem cobertura. MinHash de nomes **não é agrupamento semântico por conteúdo**, e Jaccard=1 não prova que os bytes sejam iguais. O método propõe relações para revisão, sem reorganização física automática.

Para aproveitar assinaturas salvas anteriormente:

```powershell
python .\tools\organize_inventory.py "D:\RELATORIO_NOVO\inventario.csv" --previous-catalog "C:\MAPA_ANTERIOR\catalogo.json" --output "$env:USERPROFILE\Desktop\Mapa-backup-seguinte" --open
```

Em `--watch`, a própria sessão aproveita assinaturas da análise anterior e verifica alterações dos metadados finais, além do CSV. Não é necessário Python para gerar Merkle ou executar o backup; apenas para o painel e MinHash. Bibliotecas Python externas não são necessárias.

## Referências e limites do prompt de pesquisa

- [Restic: detecção de mudanças](https://restic.readthedocs.io/en/stable/040_backup.html#file-change-detection): diferencia conteúdo presumidamente inalterado por metadados e releitura forçada. Nosso modo de backup mantém releitura para confirmar conteúdo.
- [Datasketch: MinHash LSH](https://ekzhu.com/datasketch/lsh.html): bandas, seleção aproximada e possibilidade de falsos positivos/negativos. O projeto usa implementação própria limitada, sem dependência dessa biblioteca.

O prompt mistura descoberta de duplicatas com verificação de backup. Pular hashes de tamanhos únicos pode servir ao primeiro objetivo, mas não assegura o segundo. SHA-256 oferece evidência criptográfica forte; não é comparação literal byte a byte nem uma garantia matemática de ausência de colisões. Compressão e fragmentação de arquivos não foram adicionadas nesta etapa.
