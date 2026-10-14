# Guia rápido

Para quem quer proteger documentos, fotos e projetos sem precisar entender os detalhes técnicos. Windows 10 ou 11.

> **Ordem recomendada:** configurar → simular → fazer backup → abrir alguns arquivos no HD para confirmar que dá para restaurar.

## Antes de começar

- **Um HD ou SSD externo USB**, com espaço para tudo o que você vai copiar (de preferência o dobro, para guardar versões antigas).
- O HD precisa estar **formatado em NTFS**. Para conferir: no Explorador de Arquivos, clique com o botão direito no HD › **Propriedades** › “Sistema de arquivos”. HDs novos costumam vir como **exFAT**. Para mudar para NTFS é preciso **formatar, o que apaga tudo o que está no HD** — copie antes o que houver nele. O programa nunca formata discos.
- **Feche** programas que estejam com arquivos abertos (Outlook, bancos de dados, máquinas virtuais). Arquivos em uso não podem ser copiados com segurança.

## Instalar

Baixe o [ZIP da versão atual](https://github.com/eduardoapgomes/windows-backup-audit/archive/refs/heads/main.zip), clique com o botão direito › **Extrair tudo** e escolha uma pasta fixa, por exemplo `Documentos\windows-backup-audit`. **Extraia a pasta inteira**: o programa precisa de `Iniciar.cmd`, `Backup.ps1` e da pasta `src` juntos. Quem usa Git: veja [Instalar e atualizar](ATUALIZAR.md).

Abra **`Iniciar.cmd`** (dois cliques). Se o Windows mostrar “O Windows protegeu o computador”, clique em **Mais informações › Executar assim mesmo** — isso acontece com qualquer programa baixado da internet.

## Passo 1 — Configurar (opção 4)

1. Conecte o HD externo.
2. No menu, escolha **4**. O programa procura suas pastas de dados — só confere se existem, não lê nada — e mostra a lista.
3. Ele lista os HDs conectados e diz quais podem receber o backup (e, para os outros, o motivo). Digite o número do HD.
4. O arquivo `configuracao.txt` abre no **Bloco de Notas**. Confira:
   - **Para não copiar uma pasta:** apague a linha ou coloque `#` no começo.
   - **Para acrescentar uma pasta:** escreva o caminho completo em uma linha nova, abaixo de `[ORIGENS]`. Dica: no Explorador, segure **Shift**, clique com o botão direito na pasta › **Copiar como caminho** e cole (as aspas podem ficar).
   - **Para escolher o nome da pasta no HD:** `D:\Fotos > Fotos-D`.
   - **Para ignorar uma subpasta:** escreva o nome dela (vale em qualquer nível) ou o caminho completo em `[EXCLUIR_PASTAS]`.
5. **Salve (Ctrl+S)**, volte à janela do programa e pressione Enter. Ele confere a configuração e aponta, linha por linha, qualquer problema.

Para mudar depois: opção **4** de novo › “Editar as pastas” ou “Trocar o HD de destino”.

> Usava a **versão 1** deste programa? A opção 4 importa suas pastas do `backup.local.json`, e o primeiro backup aproveita as cópias que já estão no HD (veja [Instalar e atualizar](ATUALIZAR.md)).

## Passo 2 — Simular (opção 2)

Mostra, para cada pasta, quantos arquivos são **novos**, **alterados**, **movidos** ou **sem mudança**, e quanto será copiado. **Nada é gravado no HD.** A lista completa fica em `relatorios\simulacao-<data>.tsv`, na pasta do programa (abre no Excel).

## Passo 3 — Fazer o backup (opção 1)

Na primeira vez, o programa confirma a criação da pasta no HD. Depois:

1. Lista as pastas e compara com o que já está no HD.
2. Guarda em `_VERSOES_ANTERIORES` a versão antiga dos arquivos que mudaram.
3. Copia com o Robocopy só o que falta (a barra de progresso mostra quanto já foi gravado).
4. Confere cada arquivo copiado por SHA-256.
5. Abre o relatório no navegador.

**A primeira vez demora** (é tudo novo). As seguintes costumam levar poucos minutos. **Não desconecte o HD** durante o backup. Se precisar parar, feche a janela: na próxima vez o programa continua de onde parou, sem ler de novo o que já foi conferido.

## Passo 4 — Ler o relatório

O título diz o resultado:

| Título | O que fazer |
|---|---|
| **Backup concluído e conferido** | Nada. Está tudo no HD. |
| **Concluído com avisos** | Há arquivos **só na nuvem** (OneDrive) que não foram copiados. Veja abaixo como incluí-los. |
| **Concluído com ERROS** | Os arquivos listados **não estão no backup**. Corrija a causa e execute de novo: só o que falta é copiado. |
| **Interrompido** | A execução parou (HD desconectado, falta de espaço…). O motivo aparece no topo. Execute de novo. |

O relatório fica no HD em `_CONTROLE\execucoes\<data>\RELATORIO.html`. A opção **6** abre o mais recente.

## Passo 5 — Tornar sistemático (opção 5)

Escolha **toda semana** ou **todo dia** e o horário. O Windows executa o backup sozinho, sem perguntas. Se o computador estiver desligado na hora, o backup roda quando ele ligar. Se o HD não estiver conectado (ou houver erros), **aparece um aviso na tela**. A primeira execução precisa ser feita pelo menu.

### Rotina recomendada

- **Backup:** toda semana (ou todo dia, se você produz muita coisa).
- **Verificar integridade (opção 3):** uma vez por mês. Relê o HD inteiro e confere cada arquivo; se algum estiver danificado, o próximo backup o copia de novo. Para uma conferência rápida, pela linha de comando: `.\Backup.ps1 -Acao Verificar -Amostra 10`.
- **Teste de restauração:** de vez em quando, abra alguns arquivos direto do HD ([Restaurar](RESTAURAR.md)).
- **Dois HDs:** tenha um segundo HD com a mesma configuração e alterne entre eles; deixe um fora de casa. O programa reconhece qual está conectado.

## Problemas comuns

**“não é um HD externo USB” / o HD não aparece na lista.** O destino precisa ser um disco USB externo, NTFS, gravável e diferente do disco das pastas copiadas. Pendrives USB também servem, se estiverem em NTFS. HDs Thunderbolt ou eSATA, que o Windows informa como discos internos, são recusados. Não há como desligar essa verificação.

**“usa exFAT; o destino precisa ser NTFS”.** Veja “Antes de começar”. Formatar apaga o HD.

**“Só na nuvem” no relatório.** No Explorador, clique com o botão direito na pasta do OneDrive › **Sempre manter neste dispositivo**, espere o download terminar e faça o backup de novo. O programa não baixa arquivos da nuvem sozinho para não encher o disco do computador.

**“Arquivo em uso por outro programa”.** Feche o programa (Outlook, por exemplo, mantém o `.pst` aberto) e execute de novo. Um arquivo oculto com nome de código na raiz do OneDrive (`.849C9593-…`) é do próprio OneDrive e fica sempre aberto: coloque o nome dele em `[EXCLUIR_ARQUIVOS]`.

**O programa parece parado e o título da janela começa com “Selecionar”.** Um clique dentro da janela preta entra no modo de seleção, e o Windows pausa o programa até você apertar **Esc**. Desde a versão 2.0.1 isso fica desligado enquanto o backup roda, e o computador também não entra em suspensão no meio.

**Projetos Python: as bibliotecas não entram no backup.** A pasta `site-packages` (o que o `pip` instala em qualquer ambiente virtual, tenha ele o nome que tiver) é excluída por padrão: são dezenas de milhares de arquivos que podem ser reinstalados. Para guardar a lista de pacotes de cada ambiente antes do backup, rode no PowerShell (troque `C:\Dados` pela sua pasta):

```powershell
Get-ChildItem C:\Dados -Recurse -Filter pyvenv.cfg -File -ErrorAction SilentlyContinue | ForEach-Object {
    $py = Join-Path $_.DirectoryName 'Scripts\python.exe'
    if (Test-Path $py) { & $py -m pip freeze | Set-Content (Join-Path $_.DirectoryName 'requirements-backup.txt') }
}
```

Para recriar um ambiente depois: `python -m venv novo-venv` e `novo-venv\Scripts\python -m pip install -r venv\requirements-backup.txt`.

**“Não foi possível ler a pasta: Acesso negado”.** É uma pasta protegida pelo Windows ou por outro usuário. Se você não precisa dela, coloque o caminho completo em `[EXCLUIR_PASTAS]`.

**“Espaço insuficiente no HD”.** Nada foi copiado nesta execução. Use um HD maior ou libere espaço; as pastas antigas em `_VERSOES_ANTERIORES` podem ser apagadas manualmente, começando pelas mais velhas.

**A energia acabou / fechei a janela no meio.** Execute o backup de novo. O que já foi conferido não é lido outra vez; uma cópia que ficou pela metade é guardada em `_VERSOES_ANTERIORES` e refeita.

**A letra do HD mudou.** Não precisa fazer nada: o programa procura a pasta do backup em todos os HDs conectados.

**“Há mais de um HD de backup conectado”.** Acontece no backup agendado quando os dois HDs do rodízio estão ligados. Deixe só um.

**“NÃO EXECUTADO”.** A mensagem logo acima explica o motivo (configuração, HD ausente…). Nada foi copiado.

**Quero copiar uma pasta de programa (perfil do Thunderbird, por exemplo).** Acrescente o caminho em `[ORIGENS]` e remova `AppData` de `[EXCLUIR_PASTAS]` se a pasta estiver dentro dela. Feche o programa antes do backup.

## O que este programa não faz

- Não faz imagem do Windows nem copia programas instalados — só as pastas da configuração.
- Não copia arquivos que estavam abertos e travados por outro programa; não faz snapshot (VSS).
- Não copia permissões de acesso (ACLs) nem arquivos criptografados com EFS de forma especial.
- Antes de formatar o computador, confira o relatório, resolva os erros e **teste abrir os arquivos no HD**.

Mais: [Segurança](SEGURANCA.md) · [Restaurar](RESTAURAR.md) · [Como funciona](COMO-FUNCIONA.md) · [Página principal](../README.md)
