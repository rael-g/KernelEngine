using KernelEngine.FileSystem.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Io.Native;

public unsafe partial struct ke_io
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_io *, const char *, ke_io_request **)")]
    public delegate* unmanaged[Cdecl]<ke_io*, sbyte*, ke_io_request**, KernelEngine.Result.Native.ke_result> read_file;

    [NativeTypeName("ke_result (*)(struct ke_io *, const char *, ke_io_request **)")]
    public delegate* unmanaged[Cdecl]<ke_io*, sbyte*, ke_io_request**, KernelEngine.Result.Native.ke_result> open;

    [NativeTypeName("ke_result (*)(struct ke_io *, ke_open_file *, uint64_t, void *, size_t, ke_io_request **)")]
    public delegate* unmanaged[Cdecl]<ke_io*, KernelEngine.FileSystem.Native.ke_open_file*, ulong, void*, nuint, ke_io_request**, KernelEngine.Result.Native.ke_result> read_at;

    [NativeTypeName("ke_result (*)(struct ke_io *, const char *, ke_io_request **)")]
    public delegate* unmanaged[Cdecl]<ke_io*, sbyte*, ke_io_request**, KernelEngine.Result.Native.ke_result> stat;

    [NativeTypeName("ke_result (*)(struct ke_io *, const char *, ke_io_request **)")]
    public delegate* unmanaged[Cdecl]<ke_io*, sbyte*, ke_io_request**, KernelEngine.Result.Native.ke_result> file_exists;

    [NativeTypeName("ke_result (*)(struct ke_io *, const char *, ke_io_request **)")]
    public delegate* unmanaged[Cdecl]<ke_io*, sbyte*, ke_io_request**, KernelEngine.Result.Native.ke_result> dir_exists;

    [NativeTypeName("ke_result (*)(struct ke_io *, const char *, ke_io_request **)")]
    public delegate* unmanaged[Cdecl]<ke_io*, sbyte*, ke_io_request**, KernelEngine.Result.Native.ke_result> list_dir;

    [NativeTypeName("ke_result (*)(struct ke_io *, const char *, const void *, size_t, ke_io_request **)")]
    public delegate* unmanaged[Cdecl]<ke_io*, sbyte*, void*, nuint, ke_io_request**, KernelEngine.Result.Native.ke_result> write_file;

    [NativeTypeName("ke_result (*)(struct ke_io *, const char *, ke_io_request **)")]
    public delegate* unmanaged[Cdecl]<ke_io*, sbyte*, ke_io_request**, KernelEngine.Result.Native.ke_result> make_dir;

    [NativeTypeName("ke_result (*)(struct ke_io *, const char *, ke_io_request **)")]
    public delegate* unmanaged[Cdecl]<ke_io*, sbyte*, ke_io_request**, KernelEngine.Result.Native.ke_result> remove;

    [NativeTypeName("ke_result (*)(struct ke_io *, const char *, const char *, ke_io_request **)")]
    public delegate* unmanaged[Cdecl]<ke_io*, sbyte*, sbyte*, ke_io_request**, KernelEngine.Result.Native.ke_result> rename;

    [NativeTypeName("bool (*)(struct ke_io *, ke_io_request *)")]
    public delegate* unmanaged[Cdecl]<ke_io*, ke_io_request*, bool> is_completed;

    [NativeTypeName("ke_result (*)(struct ke_io *, ke_io_request *, ke_io_result *)")]
    public delegate* unmanaged[Cdecl]<ke_io*, ke_io_request*, ke_io_result*, KernelEngine.Result.Native.ke_result> wait;

    [NativeTypeName("void (*)(struct ke_io *, ke_open_file *)")]
    public delegate* unmanaged[Cdecl]<ke_io*, KernelEngine.FileSystem.Native.ke_open_file*, void> close;

    [NativeTypeName("void (*)(struct ke_io *, void *)")]
    public delegate* unmanaged[Cdecl]<ke_io*, void*, void> free_bytes;

    [NativeTypeName("void (*)(struct ke_io *, ke_io_dir_entry *)")]
    public delegate* unmanaged[Cdecl]<ke_io*, ke_io_dir_entry*, void> free_entries;
}
