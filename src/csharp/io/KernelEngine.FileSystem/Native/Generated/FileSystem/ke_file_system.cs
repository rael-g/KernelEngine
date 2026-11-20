using System.Numerics;

using KernelEngine.Result.Native;

namespace KernelEngine.FileSystem.Native;

public unsafe partial struct ke_file_system
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_file_system *, const char *, ke_open_file **)")]
    public delegate* unmanaged[Cdecl]<ke_file_system*, sbyte*, ke_open_file**, KernelEngine.Result.Native.Result> open;

    [NativeTypeName("ke_result (*)(struct ke_file_system *, ke_open_file *, uint64_t *)")]
    public delegate* unmanaged[Cdecl]<ke_file_system*, ke_open_file*, ulong*, KernelEngine.Result.Native.Result> size;

    [NativeTypeName("ke_result (*)(struct ke_file_system *, ke_open_file *, uint64_t, void *, size_t, size_t *)")]
    public delegate* unmanaged[Cdecl]<ke_file_system*, ke_open_file*, ulong, void*, nuint, nuint*, KernelEngine.Result.Native.Result> read_at;

    [NativeTypeName("void (*)(struct ke_file_system *, ke_open_file *)")]
    public delegate* unmanaged[Cdecl]<ke_file_system*, ke_open_file*, void> close;

    [NativeTypeName("ke_result (*)(struct ke_file_system *, const char *, ke_file_stat *)")]
    public delegate* unmanaged[Cdecl]<ke_file_system*, sbyte*, FileStat*, KernelEngine.Result.Native.Result> stat;
}
