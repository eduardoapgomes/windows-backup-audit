function Get-ReparseTag {
    param([string]$Path)
    if (-not ('Backup.NativeMetadata' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
namespace Backup {
    public static class NativeMetadata {
        [StructLayout(LayoutKind.Sequential)]
        public struct TagInfo { public uint Attributes; public uint Tag; }
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        static extern SafeFileHandle CreateFileW(string name, uint access, uint share,
            IntPtr security, uint disposition, uint flags, IntPtr template);
        [DllImport("kernel32.dll", SetLastError=true)]
        static extern bool GetFileInformationByHandleEx(SafeFileHandle handle,
            int infoClass, out TagInfo info, uint size);
        public static uint ReadTag(string path) {
            // Metadata only; open the reparse point itself, including directories.
            using (var handle = CreateFileW(path, 0, 7, IntPtr.Zero, 3,
                0x02200000, IntPtr.Zero)) {
                if (handle.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error());
                TagInfo info;
                if (!GetFileInformationByHandleEx(handle, 9, out info, 8))
                    throw new Win32Exception(Marshal.GetLastWin32Error());
                return info.Tag;
            }
        }
    }
}
'@
    }
    [Backup.NativeMetadata]::ReadTag($Path)
}

function Test-CloudReparseTag {
    param([uint32]$Tag)
    # Only CLOUD and CLOUD_1..F. Unknown tags and name-surrogate links stay blocked.
    return (($Tag -band [uint32]4294905855) -eq [uint32]2415919130)
}

function Assert-SourceFileAvailable {
    param([string]$Path)
    Assert-PlainPath $Path -AllowCloudSource
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
    # Offline, recall-on-open and recall-on-data-access: do not read content.
    if ([long]$item.Attributes -band 0x00441000) {
        throw "Arquivo em nuvem não disponível localmente: $Path. No Explorador, escolha 'Sempre manter neste dispositivo', aguarde o download e execute novamente."
    }
}
