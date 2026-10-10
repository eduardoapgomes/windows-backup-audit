# Windows Backup Audit

**Backup de informação pessoal no Windows, com auditoria antes da cópia e verificação SHA-256.** A prioridade é proteger documentos, fotos, vídeos e projetos, **não copiar a instalação do Windows**.

> **Importante:** o modo automático é **focado**, não uma busca exaustiva de todos os discos. Pastas fora do escopo precisam ser incluídas manualmente. Não formate o computador apenas porque um relatório não mostra erros.

## Comece em 4 passos

1. No Windows 10/11, conecte um **HD/SSD USB externo NTFS**. Baixe o projeto em **Code → Download ZIP** e extraia **a pasta inteira** (ou clone com Git).
2. Abra **Iniciar.cmd**, opção **1 — Auditoria automática**. Selecione o destino externo. **Não copia arquivos de origem.**
3. Abra o **LEIA-ME.html** gerado, confira as pastas **INCLUDED**, os avisos **REVIEW**, arquivos **NEEDS_COPY** e erros. Adicione pastas importantes que ficaram de fora usando a opção **3**.
4. Só depois use a opção **2 — Backup automático**, no **mesmo destino**. Confira o novo relatório e **teste restaurar alguns arquivos**.

[Guia rápido e solução de problemas](docs/GUIA-RAPIDO.md).

### O que o modo automático examina

- Pastas conhecidas do usuário atual: Documentos, Área de Trabalho, Downloads, Imagens, Música, Vídeos, Favoritos e OneDrive quando disponível.
- Pastas de dados/projetos com nomes reconhecidos, como **Projetos, Projects, Code, Repos, Dados, Data, Trabalho, Work, Estudos, Notebooks**, no perfil e no topo dos volumes internos.
- **Não percorre** automaticamente a raiz de `C:\${b}, `C:\Users`, `AppData`, `Program Files`, `Windows`, caches ou todas as pastas de software. Outros nomes e arquivos soltos nas raízes dos discos são sinalizados para **REVIEW**, não declarados protegidos.

Uma pasta com nome incomum pode conter dados importantes: **inclua-a pelo modo manual**. O modo automático não substitui essa revisão.

### Como a auditoria ficou mais rápida

1. **Top-down:** seleciona as raízes úteis antes de enumerar arquivos. Bibliotecas Node/Python reconhecidas e caches gerados são ignorados no padrão `Exclude`; projetos, notebooks, arquivos de código próprio e manifests continuam elegíveis.
2. **Metadados primeiro:** na auditoria automática, se não existe arquivo de mesmo tamanho no backup, registra `NEEDS_COPY` **sem ler o arquivo inteiro para SHA-256**. Havendo candidatos de mesmo tamanho, usa SHA-256 para confirmar igualdade. Use `-FullAudit` se quiser hash de todos os arquivos da auditoria.
3. **Backup sem atalhos:** o modo Backup continua calculando SHA-256 e verificando cada cópia/reutilização antes de confirmá-la. Nenhum arquivo é excluído ou movido por similaridade.

**Merkle** compara hierarquicamente os inventários observados; **MinHash/LSH** sugere relações entre pastas no mapa opcional (opção 8, Python 3.9+). Nenhum deles é usado para pular a verificação de um backup. [Detalhes técnicos](docs/INCREMENTAL.md).

## Entenda os resultados

| Status | Significado |
|---|---|
| `NEEDS_COPY` | Precisa copiar. **Não é backup concluído.** Na auditoria rápida, o SHA pode estar vazio. |
| `VERIFIED` | Arquivo copiado e conferido no modo Backup. |
| `SKIP_IDENTICAL` | Cópia idêntica encontrada no destino esperado, conferida. |
| `REUSED_EXISTING` | Conteúdo igual encontrado em outro caminho do destino, conferido. |
| `ERROR` | Falha que exige revisão. |
| `REVIEW` (em `cobertura.csv`) | Local **fora do escopo automático**, não auditado. |
| `PARCIAL` | Execução interrompida ou ainda em andamento. **Não prova cobertura nem conclusão.** |

Relatórios: `DESTINO\_RELATORIOS\ID\LEIA-ME.html`, `inventario.csv`, `cobertura.csv`, `resumo.json` e, quando aplicável, `dependencias.csv`, `merkle.json`, `metricas.json`. **Não publique relatórios com caminhos pessoais.**

## Seleção manual ou uso avançado

No menu, **3** configura pastas, **4** audita a seleção e **5** faz o backup dela. É a melhor opção para pastas com nomes incomuns, dados de aplicativos, outras unidades ou um escopo exato. A configuração fica em `backup.local.json` e não deve ser enviada ao GitHub.

Comandos opcionais:

```powershell
# Auditoria automática focada e rápida
powershell.exe -NoProfile -STA -File .\Backup.ps1 -Mode Audit -AutoDiscover -SelectDestination -OpenReport

# Auditoria automática com hash de todos os arquivos selecionados
powershell.exe -NoProfile -STA -File .\Backup.ps1 -Mode Audit -AutoDiscover -FullAudit -SelectDestination

# Backup automático (hash e verificação obrigatórios)
powershell.exe -NoProfile -STA -File .\Backup.ps1 -Mode Backup -AutoDiscover -SelectDestination -OpenReport

# Inspecionar também bibliotecas regeneráveis, conscientemente
powershell.exe -NoProfile -STA -File .\Backup.ps1 -Mode Audit -AutoDiscover -FullAudit -DependencyPolicy Include -SelectDestination
```

O destino precisa ser USB/NTFS, fora das origens e em disco físico diferente. Não existe opção de desativar essa proteção. Para arquivos de nuvem, mantenha o conteúdo disponível localmente. Feche aplicativos que estejam escrevendo arquivos; bancos, WSL, máquinas virtuais e perfis de programas exigem exportações próprias.

## Falta energia, ou o menu diz que terminou?

Se a energia acabou, **não confie no relatório parcial como backup concluído**. Confira o destino e execute novamente depois de revisar as pastas: arquivos existentes só são reutilizados quando a comparação de conteúdo confirma igualdade. Não apague arquivos `.history-*` nem pastas de staging manualmente sem análise.

Se o menu informar que `Backup.ps1` não existe, confirme que `Iniciar.cmd`, `Backup.ps1` e a pasta `src` estão na mesma instalação; extraia o ZIP completo. Uma mensagem de falha **não é sucesso**.

## Limites, segurança e testes

Este projeto **não é imagem do Windows, snapshot VSS nem sistema completo de restauração**. Ele não assegura consistência de bancos abertos, permissões/ACLs, certificados, EFS ou dados que ficaram fora das pastas selecionadas. Antes de formatar: revisar cobertura, resolver erros, manter segunda cópia e testar restauração.

- [Guia rápido](docs/GUIA-RAPIDO.md) · [Cobertura e aplicativos especiais](docs/COVERAGE.md) · [Segurança, interrupções e retomada](docs/SAFETY.md)
- [Merkle, MinHash e custos](docs/INCREMENTAL.md) · [Mapa visual opcional](docs/ORGANIZATION.md) · [Validação e testes](docs/VALIDATION.md)
- [Pesquisa de agrupamentos](docs/HIERARCHY.md) · [Publicação segura](docs/GITHUB.md)

Testes de desenvolvimento (Windows PowerShell 5.1, Pester 5.7.1):

```powershell
Install-Module Pester -RequiredVersion 5.7.1 -Scope CurrentUser -Force
Invoke-Pester .\tests -Output Detailed
```

Licença MIT. O código não formata discos, não usa Robocopy /MIR ou /PURGE e não remove arquivos de origem.
