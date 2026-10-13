// =============================================================================
// windows-backup-audit - motor nativo
//
// Carregado por src\Backup.Core.psm1 com Add-Type. Faz apenas o trabalho pesado
// que seria lento em PowerShell: listar milhares de arquivos, comparar listas,
// calcular SHA-256 e mover arquivos com caminhos longos.
//
// Regras de projeto:
//   * Nada aqui apaga arquivos. Mover nunca substitui um arquivo existente
//     (exceto Substituir, usado só para o manifesto, gravado ao lado).
//   * Compatível com C# 5 (compilador do .NET Framework usado pelo Windows
//     PowerShell 5.1): sem interpolação de strings, "?.", "nameof" etc.
//   * No Windows usa a API Win32 com o prefixo \\?\ para aceitar caminhos com
//     mais de 260 caracteres. Fora do Windows (apenas para testes do código)
//     usa as classes de System.IO.
// =============================================================================
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using Microsoft.Win32.SafeHandles;

namespace WindowsBackupAudit
{
    /// <summary>Um arquivo encontrado na varredura.</summary>
    public sealed class Arquivo
    {
        public string Relativo;      // caminho relativo à pasta de origem, separado por '\'
        public long Bytes;
        public long Modificado;      // data de modificação: FILETIME UTC (100 ns desde 1601)
        public uint Atributos;
        public string Estado;        // preenchido durante o backup (COPIADO, ERRO...)
        public string Mensagem;
        public string Sha256;
    }

    /// <summary>Uma linha do manifesto: arquivo conferido por SHA-256 no destino.</summary>
    public sealed class Registro
    {
        public string Relativo;
        public long Bytes;
        public long Modificado;
        public string Sha256;
        public string Verificado;    // data/hora UTC ISO 8601 da última conferência
    }

    public sealed class Manifesto
    {
        public Dictionary<string, Registro> Registros =
            new Dictionary<string, Registro>(StringComparer.OrdinalIgnoreCase);
        public string Problema;      // preenchido se o arquivo existia mas não era confiável
    }

    /// <summary>Resultado da listagem de uma pasta (origem ou destino).</summary>
    public sealed class Varredura
    {
        public Dictionary<string, Arquivo> Arquivos =
            new Dictionary<string, Arquivo>(StringComparer.OrdinalIgnoreCase);
        public List<Arquivo> SomenteNuvem = new List<Arquivo>();
        public List<string> Links = new List<string>();            // relativos (junctions, symlinks)
        public List<string> PastasExcluir = new List<string>();    // completos: o Robocopy deve ignorar
        public List<string> ArquivosExcluir = new List<string>();  // completos: o Robocopy deve ignorar
        public List<string[]> Erros = new List<string[]>();        // { relativo, mensagem }
        public long Bytes;
        public long Pastas;
    }

    /// <summary>O que fazer com cada arquivo de uma origem.</summary>
    public sealed class Plano
    {
        public string Nome;
        public Varredura Origem;
        public Varredura Destino;
        public List<Arquivo> Novos = new List<Arquivo>();      // não existem no destino
        public List<Arquivo> Alterados = new List<Arquivo>();  // existem com tamanho/data diferentes
        public List<Arquivo> Conferir = new List<Arquivo>();   // iguais por metadados, sem registro de conferência
        public List<Arquivo> Nuvem = new List<Arquivo>();      // só na nuvem e ausentes no backup
        public List<Registro> Orfaos = new List<Registro>();   // no backup, mas não mais na origem
        public List<string> Obsoletos = new List<string>();    // registros do manifesto que não valem mais
        public long SemMudanca;
        public long BytesSemMudanca;
    }

    /// <summary>Arquivo novo que é o mesmo conteúdo de um arquivo que sumiu da origem (renomeado/movido).</summary>
    public sealed class Movimento
    {
        public Plano PlanoNovo;
        public Arquivo Novo;
        public Plano PlanoAntigo;
        public Registro Antigo;
    }

    public sealed class Estado
    {
        public bool Pasta;
        public long Bytes;
        public long Modificado;
        public uint Atributos;
    }

    public sealed class Resultado
    {
        public string HashOrigem;
        public string HashDestino;
        public long Bytes;
        public long Modificado;
        public string Erro;
        public bool ConteudoDiferente;
        public bool Ok { get { return Erro == null; } }
    }

    /// <summary>Padrões de exclusão no mesmo formato do Robocopy (/XD e /XF).</summary>
    public sealed class Filtro
    {
        private readonly List<Regex> pastasPorNome = new List<Regex>();
        private readonly List<Regex> pastasPorCaminho = new List<Regex>();
        private readonly List<Regex> arquivosPorNome = new List<Regex>();
        private readonly List<Regex> arquivosPorCaminho = new List<Regex>();

        public Filtro(string[] pastas, string[] arquivos)
        {
            Adicionar(pastas, pastasPorNome, pastasPorCaminho);
            Adicionar(arquivos, arquivosPorNome, arquivosPorCaminho);
        }

        private static void Adicionar(string[] padroes, List<Regex> porNome, List<Regex> porCaminho)
        {
            if (padroes == null) return;
            foreach (string bruto in padroes)
            {
                if (bruto == null) continue;
                string p = bruto.Trim();
                if (p.Length == 0) continue;
                // Com separador: compara com o caminho completo. Sem: com o nome, em qualquer nível.
                if (p.IndexOf('\\') >= 0 || p.IndexOf('/') >= 0)
                    porCaminho.Add(Glob(p.TrimEnd('\\', '/')));
                else
                    porNome.Add(Glob(p));
            }
        }

        public static Regex Glob(string padrao)
        {
            string r = "^" + Regex.Escape(padrao).Replace(@"\*", ".*").Replace(@"\?", ".") + "$";
            return new Regex(r, RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        }

        private static bool Algum(List<Regex> lista, string texto)
        {
            for (int i = 0; i < lista.Count; i++) if (lista[i].IsMatch(texto)) return true;
            return false;
        }

        public bool ExcluiPasta(string nome, string completo)
        {
            return Algum(pastasPorNome, nome) || Algum(pastasPorCaminho, completo);
        }

        public bool ExcluiArquivo(string nome, string completo)
        {
            return Algum(arquivosPorNome, nome) || Algum(arquivosPorCaminho, completo);
        }
    }

    public static class Nativo
    {
        public static readonly bool Windows = Path.DirectorySeparatorChar == '\\';
        public static readonly char Sep = Path.DirectorySeparatorChar;

        // Atributos de arquivo do Windows.
        public const uint PASTA = 0x10;
        public const uint REPARSE = 0x400;
        // Arquivo apenas na nuvem (OneDrive "Disponível online", Dropbox etc.):
        // OFFLINE | RECALL_ON_OPEN | RECALL_ON_DATA_ACCESS. Ler o conteúdo baixaria o arquivo.
        public const uint SOMENTE_NUVEM = 0x1000 | 0x40000 | 0x400000;

        // ------------------------------------------------------------------ Win32
        [StructLayout(LayoutKind.Sequential)]
        private struct FT { public uint Baixo; public uint Alto; }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct WIN32_FIND_DATAW
        {
            public uint dwFileAttributes;
            public FT ftCreationTime;
            public FT ftLastAccessTime;
            public FT ftLastWriteTime;
            public uint nFileSizeHigh;
            public uint nFileSizeLow;
            public uint dwReserved0;   // tag do reparse point
            public uint dwReserved1;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string cFileName;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 14)] public string cAlternateFileName;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct WIN32_FILE_ATTRIBUTE_DATA
        {
            public uint dwFileAttributes;
            public FT ftCreationTime;
            public FT ftLastAccessTime;
            public FT ftLastWriteTime;
            public uint nFileSizeHigh;
            public uint nFileSizeLow;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr FindFirstFileExW(string nome, int nivel, out WIN32_FIND_DATAW dados,
            int busca, IntPtr filtro, int opcoes);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool FindNextFileW(IntPtr h, out WIN32_FIND_DATAW dados);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool FindClose(IntPtr h);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool GetFileAttributesExW(string nome, int nivel, out WIN32_FILE_ATTRIBUTE_DATA dados);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern SafeFileHandle CreateFileW(string nome, uint acesso, uint compart, IntPtr seg,
            uint disposicao, uint opcoes, IntPtr modelo);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CreateDirectoryW(string nome, IntPtr seg);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool MoveFileExW(string de, string para, uint opcoes);

        private static readonly IntPtr INVALIDO = new IntPtr(-1);

        /// <summary>Prefixo \\?\ para a API Win32 aceitar caminhos longos.</summary>
        public static string Longo(string caminho)
        {
            if (!Windows || caminho.StartsWith(@"\\?\")) return caminho;
            if (caminho.StartsWith(@"\\")) return @"\\?\UNC\" + caminho.Substring(2);
            return @"\\?\" + caminho;
        }

        private static long Ticks(FT t) { return ((long)t.Alto << 32) | t.Baixo; }

        /// <summary>Mensagem curta, em português, para os erros mais comuns.</summary>
        public static string Mensagem(Exception ex)
        {
            AggregateException ag = ex as AggregateException;
            if (ag != null && ag.InnerExceptions.Count > 0) return Mensagem(ag.InnerExceptions[0]);
            Win32Exception w = ex as Win32Exception;
            if (w != null)
            {
                switch (w.NativeErrorCode)
                {
                    case 2: case 3: return "Arquivo ou pasta não encontrado.";
                    case 5: return "Acesso negado.";
                    case 32: case 33: return "Arquivo em uso por outro programa. Feche-o e execute de novo.";
                    case 112: return "Disco cheio.";
                    case 1392: return "Arquivo corrompido ou ilegível no disco.";
                }
                return w.Message + " (código " + w.NativeErrorCode + ")";
            }
            if (ex is UnauthorizedAccessException) return "Acesso negado.";
            if (ex is IOException && ex.Message.IndexOf("being used", StringComparison.OrdinalIgnoreCase) >= 0)
                return "Arquivo em uso por outro programa. Feche-o e execute de novo.";
            return ex.Message;
        }

        // ------------------------------------------------------- listagem de pastas
        private struct Entrada
        {
            public string Nome;
            public uint Atributos;
            public long Bytes;
            public long Modificado;
            public uint Tag;
        }

        private static List<Entrada> Listar(string pasta)
        {
            List<Entrada> lista = new List<Entrada>();
            if (!Windows)
            {
                foreach (FileSystemInfo i in new DirectoryInfo(pasta).GetFileSystemInfos())
                {
                    Entrada e = new Entrada();
                    e.Nome = i.Name;
                    e.Atributos = (uint)i.Attributes;
                    // Fora do Windows, um link simbólico é tratado como junction.
                    if ((e.Atributos & REPARSE) != 0) e.Tag = 0xA000000C;
                    FileInfo f = i as FileInfo;
                    if (f != null) e.Bytes = f.Length;
                    e.Modificado = i.LastWriteTimeUtc.ToFileTimeUtc();
                    lista.Add(e);
                }
                return lista;
            }
            WIN32_FIND_DATAW d;
            // 1 = FindExInfoBasic (sem nome curto), 2 = FIND_FIRST_EX_LARGE_FETCH
            IntPtr h = FindFirstFileExW(Longo(pasta) + @"\*", 1, out d, 0, IntPtr.Zero, 2);
            if (h == INVALIDO)
            {
                int erro = Marshal.GetLastWin32Error();
                if (erro == 2 || erro == 18) return lista;   // pasta vazia
                throw new Win32Exception(erro);
            }
            try
            {
                do
                {
                    if (d.cFileName == "." || d.cFileName == "..") continue;
                    Entrada e = new Entrada();
                    e.Nome = d.cFileName;
                    e.Atributos = d.dwFileAttributes;
                    e.Bytes = ((long)d.nFileSizeHigh << 32) | d.nFileSizeLow;
                    e.Modificado = Ticks(d.ftLastWriteTime);
                    e.Tag = (d.dwFileAttributes & REPARSE) != 0 ? d.dwReserved0 : 0;
                    lista.Add(e);
                } while (FindNextFileW(h, out d));
                int fim = Marshal.GetLastWin32Error();
                if (fim != 18) throw new Win32Exception(fim);   // 18 = não há mais arquivos
            }
            finally { FindClose(h); }
            return lista;
        }

        /// <summary>Tags de nuvem (IO_REPARSE_TAG_CLOUD e CLOUD_1..F) são pastas/arquivos normais.</summary>
        public static bool EhNuvem(uint tag) { return (tag & 0xFFFF0FFF) == 0x9000001A; }

        /// <summary>Junction, link simbólico ou ponto de montagem: bit "name surrogate".</summary>
        public static bool EhLink(uint tag) { return (tag & 0x20000000) != 0 && !EhNuvem(tag); }

        /// <summary>
        /// Lista uma árvore de pastas sem ler o conteúdo dos arquivos.
        /// Links (junctions e symlinks) não são seguidos. Pastas que não puderam
        /// ser lidas viram erros e entram na lista que o Robocopy deve ignorar.
        /// </summary>
        public static Varredura Varrer(string raiz, Filtro filtro, bool ehOrigem)
        {
            Varredura v = new Varredura();
            raiz = raiz.TrimEnd('\\', '/');
            Stack<string> pilha = new Stack<string>();
            pilha.Push("");
            while (pilha.Count > 0)
            {
                string rel = pilha.Pop();
                string pasta = rel.Length == 0 ? raiz : raiz + Sep + rel;
                List<Entrada> itens;
                try { itens = Listar(pasta); }
                catch (Exception ex)
                {
                    v.Erros.Add(new string[] { rel.Length == 0 ? "." : rel, "Não foi possível ler a pasta: " + Mensagem(ex) });
                    if (rel.Length > 0) v.PastasExcluir.Add(pasta);
                    continue;
                }
                v.Pastas++;
                foreach (Entrada e in itens)
                {
                    string relItem = rel.Length == 0 ? e.Nome : rel + Sep + e.Nome;
                    string completo = pasta + Sep + e.Nome;
                    bool ehPasta = (e.Atributos & PASTA) != 0;
                    if (ehPasta ? filtro.ExcluiPasta(e.Nome, completo) : filtro.ExcluiArquivo(e.Nome, completo))
                        continue;
                    if ((e.Atributos & REPARSE) != 0 && EhLink(e.Tag))
                    {
                        v.Links.Add(relItem);
                        if (ehPasta) v.PastasExcluir.Add(completo); else v.ArquivosExcluir.Add(completo);
                        continue;
                    }
                    if (ehPasta) { pilha.Push(relItem); continue; }
                    Arquivo a = new Arquivo();
                    a.Relativo = relItem;
                    a.Bytes = e.Bytes;
                    a.Modificado = e.Modificado;
                    a.Atributos = e.Atributos;
                    if (ehOrigem && (e.Atributos & SOMENTE_NUVEM) != 0) { v.SomenteNuvem.Add(a); continue; }
                    v.Arquivos[relItem] = a;
                    v.Bytes += e.Bytes;
                }
            }
            return v;
        }

        // ------------------------------------------------------------ comparação
        private static bool Igual(Arquivo a, Arquivo b) { return a.Bytes == b.Bytes && a.Modificado == b.Modificado; }

        /// <summary>
        /// Compara origem, destino e manifesto sem ler conteúdo.
        ///   igual por tamanho e data + registrado no manifesto -> sem mudança (não lê nada)
        ///   igual por tamanho e data, sem registro             -> conferir por SHA-256
        ///   diferente                                          -> alterado (guarda a versão antiga e copia)
        ///   ausente no destino                                 -> novo
        /// </summary>
        public static Plano Classificar(string nome, Varredura origem, Varredura destino, Manifesto manifesto)
        {
            Plano p = new Plano();
            p.Nome = nome;
            p.Origem = origem;
            p.Destino = destino;
            Dictionary<string, Registro> reg = manifesto.Registros;
            foreach (Arquivo a in origem.Arquivos.Values)
            {
                Arquivo d;
                if (!destino.Arquivos.TryGetValue(a.Relativo, out d)) { p.Novos.Add(a); continue; }
                if (!Igual(a, d)) { p.Alterados.Add(a); continue; }
                Registro r;
                if (reg.TryGetValue(a.Relativo, out r) && r.Bytes == a.Bytes && r.Modificado == a.Modificado)
                {
                    p.SemMudanca++;
                    p.BytesSemMudanca += a.Bytes;
                }
                else p.Conferir.Add(a);
            }
            Dictionary<string, bool> nuvem = new Dictionary<string, bool>(StringComparer.OrdinalIgnoreCase);
            foreach (Arquivo a in origem.SomenteNuvem)
            {
                nuvem[a.Relativo] = true;
                Arquivo d;
                Registro r;
                // Já está no backup na mesma versão: não precisa de aviso.
                if (destino.Arquivos.TryGetValue(a.Relativo, out d) && Igual(a, d) &&
                    reg.TryGetValue(a.Relativo, out r) && r.Bytes == a.Bytes && r.Modificado == a.Modificado)
                {
                    p.SemMudanca++;
                    p.BytesSemMudanca += a.Bytes;
                }
                else p.Nuvem.Add(a);
            }
            foreach (Registro r in reg.Values)
            {
                Arquivo d;
                bool noDestino = destino.Arquivos.TryGetValue(r.Relativo, out d) &&
                                 d.Bytes == r.Bytes && d.Modificado == r.Modificado;
                if (!noDestino) { p.Obsoletos.Add(r.Relativo); continue; }
                if (!origem.Arquivos.ContainsKey(r.Relativo) && !nuvem.ContainsKey(r.Relativo)) p.Orfaos.Add(r);
            }
            return p;
        }

        private static string NomeDe(string rel)
        {
            int i = rel.LastIndexOf(Sep);
            return i < 0 ? rel : rel.Substring(i + 1);
        }

        /// <summary>
        /// Associa arquivos novos a arquivos que sumiram da origem e têm o mesmo tamanho
        /// e data (pasta renomeada ou movida). A cópia do backup é movida em vez de
        /// copiada de novo; o conteúdo é conferido por SHA-256 depois.
        /// </summary>
        public static List<Movimento> AssociarMovidos(Plano[] planos, long minimoBytes)
        {
            List<Movimento> res = new List<Movimento>();
            Dictionary<string, List<KeyValuePair<Plano, Registro>>> orfaos =
                new Dictionary<string, List<KeyValuePair<Plano, Registro>>>(StringComparer.Ordinal);
            foreach (Plano p in planos)
            {
                foreach (Registro r in p.Orfaos)
                {
                    if (r.Bytes < minimoBytes) continue;
                    string k = r.Bytes + "|" + r.Modificado;
                    List<KeyValuePair<Plano, Registro>> l;
                    if (!orfaos.TryGetValue(k, out l)) { l = new List<KeyValuePair<Plano, Registro>>(); orfaos[k] = l; }
                    l.Add(new KeyValuePair<Plano, Registro>(p, r));
                }
            }
            if (orfaos.Count == 0) return res;
            foreach (Plano p in planos)
            {
                foreach (Arquivo a in p.Novos)
                {
                    if (a.Bytes < minimoBytes) continue;
                    List<KeyValuePair<Plano, Registro>> l;
                    if (!orfaos.TryGetValue(a.Bytes + "|" + a.Modificado, out l) || l.Count == 0) continue;
                    int escolhido = 0;
                    for (int i = 0; i < l.Count; i++)
                    {
                        if (string.Equals(NomeDe(l[i].Value.Relativo), NomeDe(a.Relativo), StringComparison.OrdinalIgnoreCase))
                        { escolhido = i; break; }
                    }
                    Movimento m = new Movimento();
                    m.PlanoNovo = p;
                    m.Novo = a;
                    m.PlanoAntigo = l[escolhido].Key;
                    m.Antigo = l[escolhido].Value;
                    l.RemoveAt(escolhido);
                    res.Add(m);
                }
            }
            return res;
        }

        // ------------------------------------------------------- estado e SHA-256
        public static Estado Info(string caminho)
        {
            if (!Windows)
            {
                FileInfo f = new FileInfo(caminho);
                if (f.Exists)
                {
                    Estado e = new Estado();
                    e.Bytes = f.Length;
                    e.Modificado = f.LastWriteTimeUtc.ToFileTimeUtc();
                    e.Atributos = (uint)f.Attributes;
                    return e;
                }
                if (Directory.Exists(caminho)) { Estado e = new Estado(); e.Pasta = true; return e; }
                return null;
            }
            WIN32_FILE_ATTRIBUTE_DATA d;
            if (!GetFileAttributesExW(Longo(caminho), 0, out d))
            {
                int erro = Marshal.GetLastWin32Error();
                // 2/3: não existe; 15: unidade inexistente; 21: unidade não está pronta
                if (erro == 2 || erro == 3 || erro == 15 || erro == 21) return null;
                throw new Win32Exception(erro);
            }
            Estado s = new Estado();
            s.Pasta = (d.dwFileAttributes & PASTA) != 0;
            s.Bytes = ((long)d.nFileSizeHigh << 32) | d.nFileSizeLow;
            s.Modificado = Ticks(d.ftLastWriteTime);
            s.Atributos = d.dwFileAttributes;
            return s;
        }

        private static Stream AbrirLeitura(string caminho)
        {
            if (!Windows)
                return new FileStream(caminho, FileMode.Open, FileAccess.Read, FileShare.Read, 1 << 20, FileOptions.SequentialScan);
            // GENERIC_READ, compartilhamento só de leitura (ninguém grava enquanto lemos),
            // OPEN_EXISTING, FILE_FLAG_SEQUENTIAL_SCAN.
            SafeFileHandle h = CreateFileW(Longo(caminho), 0x80000000, 1, IntPtr.Zero, 3, 0x08000000, IntPtr.Zero);
            if (h.IsInvalid)
            {
                int erro = Marshal.GetLastWin32Error();
                h.Dispose();
                throw new Win32Exception(erro);
            }
            return new FileStream(h, FileAccess.Read, 1 << 20);
        }

        private static HashAlgorithm NovoSha256()
        {
            // No .NET Framework, SHA256.Create() devolve a implementação gerenciada, lenta.
            // SHA256Cng usa a criptografia do Windows (com instruções SHA da CPU, quando houver).
            try
            {
                Type t = Type.GetType("System.Security.Cryptography.SHA256Cng, System.Core, Version=4.0.0.0, Culture=neutral, PublicKeyToken=b77a5c561934e089", false);
                if (t != null) return (HashAlgorithm)Activator.CreateInstance(t);
            }
            catch (Exception) { }
            return SHA256.Create();
        }

        public static string Sha256(string caminho)
        {
            using (Stream s = AbrirLeitura(caminho))
            using (HashAlgorithm sha = NovoSha256())
            {
                byte[] buffer = new byte[1 << 20];
                int lidos;
                while ((lidos = s.Read(buffer, 0, buffer.Length)) > 0) sha.TransformBlock(buffer, 0, lidos, null, 0);
                sha.TransformFinalBlock(buffer, 0, 0);
                return Hex(sha.Hash);
            }
        }

        public static string Sha256Texto(string texto)
        {
            using (HashAlgorithm sha = NovoSha256())
                return Hex(sha.ComputeHash(new UTF8Encoding(false).GetBytes(texto)));
        }

        private static string Hex(byte[] b)
        {
            StringBuilder sb = new StringBuilder(b.Length * 2);
            foreach (byte x in b) sb.Append(x.ToString("x2"));
            return sb.ToString();
        }

        /// <summary>
        /// Confere uma cópia: mesmo tamanho e data, e o mesmo SHA-256 lido dos dois discos
        /// ao mesmo tempo. Também confirma que a origem não mudou durante a leitura.
        /// </summary>
        public static Resultado Verificar(string origem, string destino)
        {
            Resultado r = new Resultado();
            try
            {
                Estado a1 = Info(origem);
                if (a1 == null || a1.Pasta) { r.Erro = "O arquivo não existe mais na origem."; return r; }
                Estado b = Info(destino);
                if (b == null || b.Pasta) { r.Erro = "Não foi copiado para o destino (veja o log do Robocopy)."; return r; }
                if (a1.Bytes != b.Bytes) { r.Erro = "Tamanho diferente no destino. O arquivo pode ter mudado durante a cópia."; r.ConteudoDiferente = true; return r; }
                if (a1.Modificado != b.Modificado) { r.Erro = "Data de modificação diferente no destino. O arquivo pode ter mudado durante a cópia."; r.ConteudoDiferente = true; return r; }
                Task<string> tarefa = Task.Factory.StartNew<string>(delegate { return Sha256(origem); }, TaskCreationOptions.LongRunning);
                string hDestino;
                try { hDestino = Sha256(destino); }
                finally { try { tarefa.Wait(); } catch (Exception) { } }
                string hOrigem = tarefa.Result;
                Estado a2 = Info(origem);
                if (a2 == null || a2.Bytes != a1.Bytes || a2.Modificado != a1.Modificado)
                { r.Erro = "A origem mudou durante a verificação. Execute de novo."; return r; }
                r.HashOrigem = hOrigem;
                r.HashDestino = hDestino;
                r.Bytes = a1.Bytes;
                r.Modificado = a1.Modificado;
                if (hOrigem != hDestino) { r.Erro = "Conteúdo diferente: o SHA-256 da cópia não confere com a origem."; r.ConteudoDiferente = true; }
            }
            catch (Exception ex) { r.Erro = Mensagem(ex); }
            return r;
        }

        public static Resultado[] VerificarLote(string[] origens, string[] destinos, int paralelo)
        {
            Resultado[] res = new Resultado[origens.Length];
            ParallelOptions op = new ParallelOptions();
            op.MaxDegreeOfParallelism = Math.Max(1, paralelo);
            Parallel.For(0, origens.Length, op, delegate (int i) { res[i] = Verificar(origens[i], destinos[i]); });
            return res;
        }

        /// <summary>Relê uma cópia do backup e compara com o SHA-256 do manifesto.</summary>
        public static Resultado Conferir(string caminho, long bytes, string sha)
        {
            Resultado r = new Resultado();
            try
            {
                Estado e = Info(caminho);
                if (e == null || e.Pasta) { r.Erro = "Arquivo ausente no backup."; return r; }
                if (e.Bytes != bytes) { r.Erro = "Tamanho diferente do registrado."; r.ConteudoDiferente = true; return r; }
                r.HashDestino = Sha256(caminho);
                r.Bytes = e.Bytes;
                r.Modificado = e.Modificado;
                if (!string.Equals(r.HashDestino, sha, StringComparison.OrdinalIgnoreCase))
                { r.Erro = "Conteúdo alterado: o SHA-256 não confere com o registrado."; r.ConteudoDiferente = true; }
            }
            catch (Exception ex) { r.Erro = Mensagem(ex); }
            return r;
        }

        public static Resultado[] ConferirLote(string[] caminhos, long[] bytes, string[] shas, int paralelo)
        {
            Resultado[] res = new Resultado[caminhos.Length];
            ParallelOptions op = new ParallelOptions();
            op.MaxDegreeOfParallelism = Math.Max(1, paralelo);
            Parallel.For(0, caminhos.Length, op, delegate (int i) { res[i] = Conferir(caminhos[i], bytes[i], shas[i]); });
            return res;
        }

        // ------------------------------------------------------------ mover
        public static void CriarPastas(string pasta)
        {
            if (!Windows) { Directory.CreateDirectory(pasta); return; }
            pasta = pasta.TrimEnd('\\');
            Estado e = Info(pasta);
            if (e != null)
            {
                if (!e.Pasta) throw new IOException("Existe um arquivo com o nome da pasta: " + pasta);
                return;
            }
            int i = pasta.LastIndexOf('\\');
            if (i > 2) CriarPastas(pasta.Substring(0, i));
            if (!CreateDirectoryW(Longo(pasta), IntPtr.Zero))
            {
                int erro = Marshal.GetLastWin32Error();
                if (erro != 183) throw new Win32Exception(erro);   // 183 = já existe
            }
        }

        /// <summary>Move um arquivo dentro do mesmo disco. Nunca substitui: falha se o destino existir.</summary>
        public static void Mover(string de, string para)
        {
            int i = para.LastIndexOf(Sep);
            if (i > 0) CriarPastas(para.Substring(0, i));
            if (!Windows)
            {
                if (File.Exists(para) || Directory.Exists(para)) throw new IOException("O destino já existe: " + para);
                File.Move(de, para);
                return;
            }
            if (!MoveFileExW(Longo(de), Longo(para), 0x8)) throw new Win32Exception(Marshal.GetLastWin32Error());
        }

        /// <summary>Troca um arquivo por outro de forma atômica (usado só para o manifesto).</summary>
        public static void Substituir(string novo, string final)
        {
            if (!Windows)
            {
                if (File.Exists(final)) File.Delete(final);
                File.Move(novo, final);
                return;
            }
            // MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH
            if (!MoveFileExW(Longo(novo), Longo(final), 0x1 | 0x8)) throw new Win32Exception(Marshal.GetLastWin32Error());
        }

        // ------------------------------------------------------------ manifesto
        private const string Cabecalho = "# windows-backup-audit manifesto 2";

        /// <summary>
        /// Lê o manifesto. A última linha contém o SHA-256 de todas as anteriores; se não
        /// conferir (arquivo truncado ou editado), o manifesto é ignorado e os arquivos
        /// serão conferidos de novo por SHA-256. Isso é lento, mas sempre seguro.
        /// </summary>
        public static Manifesto LerManifesto(string caminho)
        {
            Manifesto m = new Manifesto();
            if (!File.Exists(caminho)) return m;
            List<Registro> lidos = new List<Registro>();
            string esperado = null;
            bool depoisDoFim = false;
            using (HashAlgorithm sha = NovoSha256())
            using (StreamReader leitor = new StreamReader(caminho, new UTF8Encoding(false), false))
            {
                string linha;
                int numero = 0;
                while ((linha = leitor.ReadLine()) != null)
                {
                    numero++;
                    if (depoisDoFim) { if (linha.Length > 0) { m.Problema = "Há conteúdo depois da linha final."; } continue; }
                    if (linha.StartsWith("# fim "))
                    {
                        int k = linha.IndexOf("sha256=");
                        esperado = k < 0 ? "" : linha.Substring(k + 7).Trim();
                        depoisDoFim = true;
                        continue;
                    }
                    byte[] b = Encoding.UTF8.GetBytes(linha + "\n");
                    sha.TransformBlock(b, 0, b.Length, null, 0);
                    if (numero == 1 && linha != Cabecalho) { m.Problema = "Formato de manifesto desconhecido."; break; }
                    if (linha.Length == 0 || linha[0] == '#') continue;
                    string[] c = linha.Split('\t');
                    long bytes, mod;
                    if (c.Length < 5 || !long.TryParse(c[1], out bytes) || !long.TryParse(c[2], out mod) || c[3].Length != 64)
                    { m.Problema = "Linha " + numero + " inválida."; break; }
                    Registro r = new Registro();
                    r.Relativo = c[0]; r.Bytes = bytes; r.Modificado = mod; r.Sha256 = c[3]; r.Verificado = c[4];
                    lidos.Add(r);
                }
                sha.TransformFinalBlock(new byte[0], 0, 0);
                if (m.Problema == null)
                {
                    if (esperado == null) m.Problema = "Manifesto incompleto (gravação interrompida).";
                    else if (!string.Equals(esperado, Hex(sha.Hash), StringComparison.OrdinalIgnoreCase))
                        m.Problema = "O SHA-256 do manifesto não confere (arquivo alterado ou corrompido).";
                }
            }
            if (m.Problema == null) foreach (Registro r in lidos) m.Registros[r.Relativo] = r;
            return m;
        }

        /// <summary>Grava em arquivo temporário e troca de uma vez: nunca deixa um manifesto pela metade.</summary>
        public static void GravarManifesto(string caminho, Manifesto m)
        {
            string tmp = caminho + ".tmp";
            List<string> chaves = new List<string>(m.Registros.Keys);
            chaves.Sort(StringComparer.OrdinalIgnoreCase);
            using (HashAlgorithm sha = NovoSha256())
            {
                using (FileStream fs = new FileStream(tmp, FileMode.Create, FileAccess.Write, FileShare.None, 1 << 16))
                using (StreamWriter w = new StreamWriter(fs, new UTF8Encoding(false)))
                {
                    w.NewLine = "\n";
                    Escrever(w, sha, Cabecalho);
                    Escrever(w, sha, "# caminho\tbytes\tmodificado_filetime_utc\tsha256\tverificado_utc");
                    foreach (string k in chaves)
                    {
                        Registro r = m.Registros[k];
                        Escrever(w, sha, r.Relativo + "\t" + r.Bytes + "\t" + r.Modificado + "\t" + r.Sha256 + "\t" + r.Verificado);
                    }
                    sha.TransformFinalBlock(new byte[0], 0, 0);
                    w.WriteLine("# fim " + chaves.Count + " registros sha256=" + Hex(sha.Hash));
                    w.Flush();
                    fs.Flush(true);
                }
            }
            Substituir(tmp, caminho);
        }

        private static void Escrever(StreamWriter w, HashAlgorithm sha, string linha)
        {
            byte[] b = Encoding.UTF8.GetBytes(linha + "\n");
            sha.TransformBlock(b, 0, b.Length, null, 0);
            w.WriteLine(linha);
        }
    }
}
