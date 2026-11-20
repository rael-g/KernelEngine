using System.Numerics;

using global::KernelEngine.Assembly;
using global::KernelEngine.Logger;

using KernelEngine.Part.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Assembly.Native;

public unsafe partial struct ke_assembly
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_assembly *, ke_log_callback, void *)")]
    public delegate* unmanaged[Cdecl]<ke_assembly*, delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void>, void*, KernelEngine.Result.Native.Result> route_log;

    [NativeTypeName("ke_result (*)(struct ke_assembly *, const ke_part *)")]
    public delegate* unmanaged[Cdecl]<ke_assembly*, KernelEngine.Part.Native.ke_part*, KernelEngine.Result.Native.Result> add_part;

    [NativeTypeName("ke_result (*)(struct ke_assembly *, const char *, const char *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_assembly*, sbyte*, sbyte*, sbyte*, KernelEngine.Result.Native.Result> add_instance;

    [NativeTypeName("ke_result (*)(struct ke_assembly *, const char *, const char *, void *)")]
    public delegate* unmanaged[Cdecl]<ke_assembly*, sbyte*, sbyte*, void*, KernelEngine.Result.Native.Result> add_external;

    [NativeTypeName("ke_result (*)(struct ke_assembly *, const char *, const char *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_assembly*, sbyte*, sbyte*, sbyte*, KernelEngine.Result.Native.Result> bind;

    [NativeTypeName("ke_result (*)(struct ke_assembly *, const char *, const char *, const char *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_assembly*, sbyte*, sbyte*, sbyte*, sbyte*, KernelEngine.Result.Native.Result> order;

    [NativeTypeName("ke_result (*)(struct ke_assembly *, const char *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_assembly*, sbyte*, sbyte*, KernelEngine.Result.Native.Result> set_default;

    [NativeTypeName("ke_result (*)(struct ke_assembly *, ke_assembly_report_fn, void *)")]
    public delegate* unmanaged[Cdecl]<ke_assembly*, delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Assembly.AssemblyFailure, sbyte*, sbyte*, sbyte*, void>, void*, KernelEngine.Result.Native.Result> resolve;

    [NativeTypeName("ke_result (*)(struct ke_assembly *)")]
    public delegate* unmanaged[Cdecl]<ke_assembly*, KernelEngine.Result.Native.Result> advance;

    [NativeTypeName("ke_result (*)(struct ke_assembly *, const char *, const char *, void **)")]
    public delegate* unmanaged[Cdecl]<ke_assembly*, sbyte*, sbyte*, void**, KernelEngine.Result.Native.Result> get;
}
