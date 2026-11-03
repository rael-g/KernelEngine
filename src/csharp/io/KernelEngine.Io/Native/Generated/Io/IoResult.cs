using System.Numerics;

using KernelEngine.FileSystem.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Io.Native;

public unsafe partial struct IoResult
{
    [NativeTypeName("ke_open_file *")]
    public KernelEngine.FileSystem.Native.ke_open_file* File;

    public void* Bytes;

    [NativeTypeName("uint64_t")]
    public ulong Size;

    [NativeTypeName("ke_file_stat")]
    public KernelEngine.FileSystem.Native.FileStat Stat;

    public bool Exists;

    [NativeTypeName("ke_io_dir_entry *")]
    public IoDirEntry* Entries;

    [NativeTypeName("uint32_t")]
    public uint EntryCount;
}
