# Windows Backup Audit

[![Testes no Windows](https://github.com/eduardoapgomes/windows-backup-audit/actions/workflows/tests.yml/badge.svg)](https://github.com/eduardoapgomes/windows-backup-audit/actions/workflows/tests.yml)

**Backup sistemático das suas pastas para um HD externo — rápido, conferido arquivo por arquivo e sem apagar nada.**

Para Windows 10 e 11. Não precisa instalar nada além do próprio programa: usa o PowerShell e o Robocopy que já vêm no Windows.

- **Copia só o que mudou.** A primeira vez copia tudo; nas seguintes, só os arquivos novos ou alterados — normalmente minutos.
- **Confere cada cópia.** Depois de copiar, lê o arquivo na origem e no HD e compara o SHA-256 (a “impressão digital” do conteúdo).
- **Nunca apaga e nunca sobrescreve.** Quando um arquivo muda, a versão antiga do backup vai para `_VERSOES_ANTERIORES`. Arquivos apagados no computador continuam no HD.
- **Pasta renomeada não é copiada de novo.** O programa percebe que é o mesmo conteúdo e só move a cópia dentro do HD.
- **O backup é uma cópia comum de pastas.** Para restaurar, basta abrir o HD no Explorador de Arquivos. Nenhum formato especial.

## Começar em 4 passos

1. **Instale.** Baixe o [ZIP](https://github.com/eduardoapgomes/windows-backup-audit/archive/refs/heads/main.zip) e extraia **a pasta inteira** em um lugar fixo (por exemplo, `Documentos\windows-backup-audit`). Quem usa Git pode clonar; veja [Instalar e atualizar](docs/ATUALIZAR.md).
2. **Configure.** Conecte o **HD externo USB (NTFS)**, abra **`Iniciar.cmd`** e escolha **4 – Configurar**. O programa sugere suas pastas (Documentos, Área de Trabalho, Imagens, Vídeos, Downloads, OneDrive, Projetos…), pergunta qual HD usar e abre a lista no Bloco de Notas para você conferir.
3. **Simule e faça o backup.** Escolha **2 – Simular** para ver quanto será copiado, sem gravar nada. Depois **1 – Fazer backup**. Ao terminar, o relatório abre no navegador.
4. **Torne sistemático.** Escolha **5 – Agendar** (toda semana ou todo dia). Uma vez por mês, use **3 – Verificar integridade**. Abra de vez em quando alguns arquivos direto do HD.

Passo a passo detalhado e solução de problemas: **[Guia rápido](docs/GUIA-RAPIDO.md)**.

## Menu

| Opção | O que faz |
|---|---|
| **1. Fazer backup agora** | Copia o que é novo ou mudou, guarda versões anteriores e confere tudo por SHA-256 |
| **2. Simular** | Mostra o que seria copiado, atualizado ou movido. **Não grava nada no HD** |
| **3. Verificar integridade** | Relê o HD e confere cada arquivo com o SHA-256 registrado quando foi copiado |
| **4. Configurar** | Cria ou edita `configuracao.txt` (pastas, HD de destino, exclusões) |
| **5. Agendar** | Cria ou remove o backup automático no Agendador de Tarefas do Windows |
| **6. Abrir o último relatório** | Abre o relatório da última execução gravado no HD |

## A configuração é um texto simples

`configuracao.txt` fica na pasta do programa e pode ser editado no Bloco de Notas — sem aspas, sem barras duplicadas ([exemplo completo](configuracao.exemplo.txt)):

```ini
[DESTINO]
E:\BACKUP_WINDOWS\MEU-PC-ana

[ORIGENS]
C:\Users\ana\Documents
C:\Users\ana\Pictures
D:\Projetos > D_Projetos

[EXCLUIR_PASTAS]
node_modules
__pycache__

[EXCLUIR_ARQUIVOS]
~$*
*.tmp
```

Cada linha de `[ORIGENS]` vira uma pasta no HD. `> Nome` escolhe outro nome. Se a letra do HD mudar (E: hoje, F: amanhã), o programa encontra a mesma pasta sozinho.

## O que fica no HD

```text
E:\BACKUP_WINDOWS\MEU-PC-ana\
├── Documents\                     cópia comum da pasta Documents
├── Pictures\
├── D_Projetos\
├── _VERSOES_ANTERIORES\           versões antigas de arquivos que mudaram (por data)
├── _CONTROLE\
│   ├── manifestos\                SHA-256, tamanho e data de cada arquivo conferido
│   ├── execucoes\<data>\          RELATORIO.html, detalhes.tsv, resumo.json, logs do Robocopy
│   └── ULTIMO-RELATORIO.html      atalho para o relatório mais recente
└── LEIA-ME.txt                    explica esta estrutura para quem abrir o HD
```

## Como ler o resultado

| No relatório | Significado |
|---|---|
| **Sem mudança** | Já estava no backup, igual. Não foi lido de novo |
| **Copiados** | Arquivos novos, copiados e conferidos |
| **Atualizados** | Mudaram desde o último backup; a versão anterior está em `_VERSOES_ANTERIORES` |
| **Movidos** | Só mudaram de pasta ou de nome; a cópia foi movida no HD e conferida |
| **Conferidos** | Já estavam no HD (backup antigo ou execução interrompida) e foram conferidos por SHA-256 |
| **Só na nuvem** | Arquivos do OneDrive não baixados neste computador: **não foram copiados** (aviso) |
| **Erros** | **Não estão no backup**: arquivo aberto em outro programa, pasta sem permissão, HD desconectado |

O menu e o `Backup.ps1` terminam com um código: **0** tudo certo · **1** avisos (só na nuvem) · **2** erros ou interrompido · **3** não executado (configuração ou HD).

## Segurança

- **Destino só em HD externo USB, NTFS**, em disco físico diferente das pastas copiadas, que não seja o disco do Windows. Não há opção para desligar essa verificação.
- O Robocopy só cria arquivos que **não existem** no HD (`/XC /XN /XO`); não usa `/MIR` nem `/PURGE`. A versão antiga de um arquivo alterado é **movida** para `_VERSOES_ANTERIORES` antes da cópia nova.
- Cada cópia é conferida por SHA-256 lendo a origem e o HD. O manifesto tem seu próprio SHA-256 e é gravado de forma atômica; se for danificado, o programa confere tudo de novo em vez de confiar nele.
- Antes de gravar, confere que o HD ainda é o mesmo (identidade do disco). Duas execuções no mesmo HD ao mesmo tempo são bloqueadas.
- Arquivos “só na nuvem” não são baixados; links e junções do Windows não são seguidos.

**Limites:** não é imagem do Windows nem snapshot (VSS); arquivos abertos e bancos de dados em uso podem falhar ou ficar inconsistentes — feche os programas antes. Permissões (ACLs) não são copiadas. Detalhes, ransomware e boas práticas: **[Segurança](docs/SEGURANCA.md)**.

## Por que é rápido

- Lista pastas lendo **só nomes, tamanhos e datas** (API nativa do Windows), sem abrir arquivos.
- Arquivo com mesmo tamanho e data já registrado no manifesto **não é lido de novo**.
- O **Robocopy multithread** (`/MT:8`) copia; nada de um processo por arquivo.
- SHA-256 pela criptografia do Windows (usa as instruções SHA da CPU quando existem), lendo **origem e HD ao mesmo tempo**; arquivos pequenos são conferidos em paralelo.
- Bibliotecas e caches regeneráveis (`node_modules`, `__pycache__`, `.venv`, `site-packages`…) ficam fora por padrão. `.git` **não** é excluído: o histórico local de um repositório é dado seu.

Medição no Windows do CI (1.504 arquivos, 112 MB, mesmo SSD; a checagem física do HD foi simulada nas duas versões, o que favorece a versão 1):

| | Versão 1 | Versão 2 |
|---|---:|---:|
| Primeiro backup | 131 s | **6,7 s** |
| Sem mudanças | 55 s | **0,1 s** |
| 10 arquivos alterados | 56 s | **0,3 s** |

Com um HD USB, o primeiro backup é limitado pela velocidade de gravação do HD; as execuções seguintes continuam rápidas porque só leem o que mudou. Reproduza com `tests\Comparar-Desempenho.ps1`.

Como tudo funciona, passo a passo, e quais ideias do relatório de pesquisa foram adotadas (e quais não, e por quê): **[Como funciona](docs/COMO-FUNCIONA.md)**.

## Documentação

- [Guia rápido](docs/GUIA-RAPIDO.md) — uso passo a passo e solução de problemas
- [Restaurar arquivos](docs/RESTAURAR.md) — um arquivo, uma versão antiga ou o computador inteiro
- [Segurança](docs/SEGURANCA.md) — garantias, limites, ransomware, criptografia do HD
- [Como funciona](docs/COMO-FUNCIONA.md) — fluxo, manifesto, Robocopy, decisões técnicas
- [Instalar e atualizar](docs/ATUALIZAR.md) — inclusive vindo da versão 1
- [Testes](docs/TESTES.md) — testes automáticos e roteiro de teste com o seu HD
- [Mudanças](CHANGELOG.md)

## Linha de comando

```powershell
.\Backup.ps1 -Acao Simular
.\Backup.ps1 -Acao Backup
.\Backup.ps1 -Acao Verificar -Amostra 10     # confere ~10% dos arquivos, sorteados
.\Backup.ps1 -Acao Backup -Threads 16        # mais threads no Robocopy (SSD rápido)
Get-Help .\Backup.ps1 -Detailed
```

Licença MIT. Não publique `configuracao.txt` nem relatórios: eles contêm caminhos pessoais.
