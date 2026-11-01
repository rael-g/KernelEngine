using System.Numerics;

using KernelEngine.FileSystem.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Io.Native;

public unsafe partial struct ke_io
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_io *, const char *, ke_io_request **)")]
    public delegate* unmanaged[Cdecl]<ke_io*, sbyte*, ke_io_request**, KernelEngine.Result.Native.Result> read_file;

    [NativeTypeName("ke_result (*)(struct ke_io *, const char *, ke_io_request **)")]
    public delegate* unmanaged[Cdecl]<ke_io*, sbyte*, ke_io_request**, KernelEngine.Result.Native.Result> open;

    [NativeTypeName("ke_result (*)(struct ke_io *, ke_open_file *, uint64_t, void *, size_t, ke_io_request **)")]
    public delegate* unmanaged[Cdecl]<ke_io*, KernelEngine.FileSystem.Native.ke_open_file*, ulong, void*, nuint, ke_io_request**, KernelEngine.Result.Native.Result> read_at;

    [NativeTypeName("ke_result (*)(struct ke_io *, const char *, ke_io_request **)")]
    public delegate* unmanaged[Cdecl]<ke_io*, sbyte*, ke_io_request**, KernelEngine.Result.Native.Result> stat;

    [NativeTypeName("ke_result (*)(struct ke_io *, const char *, ke_io_request **)")]
    public delegate* unmanaged[Cdecl]<ke_io*, sbyte*, ke_io_request**, KernelEngine.Result.Native.Result> file_exists;

    [NativeTypeName("ke_result (*)(struct ke_io *, const char *, ke_io_request **)")]
    public delegate* unmanaged[Cdecl]<ke_io*, sbyte*, ke_io_request**, KernelEngine.Result.Native.Result> dir_exists;

    [NativeTypeName("ke_result (*)(struct ke_io *, const char *, ke_io_request **)")]
    public delegate* unmanaged[Cdecl]<ke_io*, sbyte*, ke_io_request**, KernelEngine.Result.Native.Result> list_dir;

    [NativeTypeName("ke_result (*)(struct ke_io *, const char *, const void *, size_t, ke_io_request **)")]
    public delegate* unmanaged[Cdecl]<ke_io*, sbyte*, void*, nuint, ke_io_request**, KernelEngine.Result.Native.Result> write_file;

    [NativeTypeName("ke_result (*)(struct ke_io *, const char *, ke_io_request **)")]
    public delegate* unmanaged[Cdecl]<ke_io*, sbyte*, ke_io_request**, KernelEngine.Result.Native.Result> make_dir;

    [NativeTypeName("ke_result (*)(struct ke_io *, const char *, ke_io_request **)")]
    public delegate* unmanaged[Cdecl]<ke_io*, sbyte*, ke_io_request**, KernelEngine.Result.Native.Result> remove;

    [NativeTypeName("ke_result (*)(struct ke_io *, const char *, const char *, ke_io_request **)")]
    public delegate* unmanaged[Cdecl]<ke_io*, sbyte*, sbyte*, ke_io_request**, KernelEngine.Result.Native.Result> rename;

    [NativeTypeName("bool (*)(struct ke_io *, ke_io_request *)")]
    public delegate* unmanaged[Cdecl]<ke_io*, ke_io_request*, bool> is_completed;

    [NativeTypeName("ke_result (*)(struct ke_io *, ke_io_request *, ke_io_result *)")]
    public delegate* unmanaged[Cdecl]<ke_io*, ke_io_request*, IoResult*, KernelEngine.Result.Native.Result> wait;

    [NativeTypeName("void (*)(struct ke_io *, ke_open_file *)")]
    public delegate* unmanaged[Cdecl]<ke_io*, KernelEngine.FileSystem.Native.ke_open_file*, void> close;

    [NativeTypeName("void (*)(struct ke_io *, void *)")]
    public delegate* unmanaged[Cdecl]<ke_io*, void*, void> free_bytes;

    [NativeTypeName("void (*)(struct ke_io *, ke_io_dir_entry *)")]
    public delegate* unmanaged[Cdecl]<ke_io*, IoDirEntry*, void> free_entries;
}
