# Segurança: garantias e limites

## O que o programa nunca faz

- **Nunca apaga arquivos** — nem nas pastas copiadas, nem no HD de backup.
- **Nunca sobrescreve uma cópia** no HD. Quando um arquivo muda, a versão antiga é movida para `_VERSOES_ANTERIORES\<data da execução>\` antes da cópia nova.
- **Nunca grava nas pastas de origem.** Elas são só lidas.
- **Nunca formata, particiona ou muda permissões** de discos.
- **Nunca baixa arquivos da nuvem** sozinho (OneDrive “disponível online”).
- **Nunca segue atalhos do sistema** (junções e links simbólicos), que poderiam levar a outras pastas ou a laços infinitos.

## Regras do HD de destino

O destino precisa ser, ao mesmo tempo:

- um disco **USB externo** (como o Windows o informa);
- formatado em **NTFS** e **gravável**;
- **diferente do disco do Windows** (não é o disco de inicialização nem de sistema);
- um **disco físico diferente** de todas as pastas copiadas (outra partição do mesmo disco não serve);
- uma **pasta** dentro do HD (não a raiz), sem junções ou links no caminho.

Se o Windows não consegue informar a identidade do disco, ele é recusado. Não existe opção para desligar essas regras. Antes de guardar versões antigas e antes de cada cópia, o programa confere de novo se o HD ainda é o mesmo; se ele foi trocado ou desconectado, a execução para.

## O que acontece quando algo dá errado

| Situação | Resultado | O que fazer |
|---|---|---|
| Falta de energia ou janela fechada | O que já foi conferido está no manifesto (salvo a cada minuto). Uma cópia pela metade é guardada em `_VERSOES_ANTERIORES` e refeita | Execute o backup de novo |
| HD desconectado durante o backup | A execução para com “INTERROMPIDO” | Reconecte e execute de novo |
| Arquivo aberto em outro programa | Esse arquivo fica como **erro**; os outros são copiados | Feche o programa e execute de novo |
| Pasta sem permissão de leitura | Erro para a pasta; o Robocopy também a ignora | Exclua-a em `[EXCLUIR_PASTAS]` se não precisar dela |
| HD sem espaço | Nada é copiado; a mensagem diz quanto falta | HD maior, ou apague pastas antigas de `_VERSOES_ANTERIORES` |
| Manifesto danificado ou editado | É ignorado; todos os arquivos são conferidos de novo por SHA-256 | Nada (só demora mais uma vez) |
| Arquivo corrompido no HD | A **verificação de integridade** detecta; o próximo backup guarda a cópia ruim em `_VERSOES_ANTERIORES` e copia de novo | Execute a verificação uma vez por mês |
| Duas execuções no mesmo HD | A segunda é recusada | Espere a primeira terminar |

## Proteção contra ransomware e acidentes

Um HD que fica sempre conectado pode ser criptografado junto com o computador. Por isso:

- **Conecte o HD só durante o backup** (o agendamento avisa se ele não estiver conectado).
- **Use dois HDs e alterne**, guardando um fora de casa. A configuração é a mesma; o programa reconhece o HD conectado.
- **`_VERSOES_ANTERIORES`** guarda a versão anterior de tudo o que mudou. Se arquivos forem criptografados por um vírus e o backup rodar, as versões boas continuam lá. Mesmo assim, não é substituto de uma segunda cópia desconectada.
- Antes de restaurar depois de um incidente, use **Verificar integridade** para confirmar que o HD está bom.

## Criptografia do HD

O programa não criptografa o backup. Se o HD puder ser perdido ou roubado, ative o **BitLocker To Go** (Windows Pro/Enterprise: botão direito no HD › **Ativar o BitLocker**). Guarde a chave de recuperação em local seguro e diferente do HD. O backup funciona normalmente em HDs com BitLocker, depois de desbloqueados.

## Limites

- **Não é imagem do sistema.** Programas instalados, configurações do Windows e pastas fora da configuração não são copiados.
- **Sem snapshot (VSS).** Arquivos em uso falham; bancos de dados, máquinas virtuais, WSL e perfis de e-mail devem ser fechados ou exportados pelo próprio programa antes.
- **Permissões (ACLs), dono e criptografia EFS** não são copiados.
- **Mudanças que preservam tamanho e data** não são detectadas pelo backup incremental (situação rara).
- **SHA-256** é uma evidência criptográfica fortíssima de igualdade, mas não substitui um **teste de restauração**: abra alguns arquivos direto do HD de vez em quando.
- Um programa malicioso com privilégios de administrador pode interferir em qualquer backup feito pelo próprio computador. Por isso a cópia desconectada é importante.

## Privacidade

`configuracao.txt` e os relatórios contêm nomes e caminhos de pastas pessoais. Eles não são enviados para lugar nenhum e estão no `.gitignore`; não os publique.
