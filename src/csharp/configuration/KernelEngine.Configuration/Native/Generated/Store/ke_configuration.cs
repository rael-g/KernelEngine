using System.Numerics;

using global::KernelEngine.Logger;

using KernelEngine.Result.Native;
using KernelEngine.Settings.Native;

namespace KernelEngine.Configuration.Native;

public unsafe partial struct ke_configuration
{
    public void* handle;

    [NativeTypeName("int64_t (*)(struct ke_configuration *, const char *, const char *, int64_t)")]
    public delegate* unmanaged[Cdecl]<ke_configuration*, sbyte*, sbyte*, long, long> get_int;

    [NativeTypeName("double (*)(struct ke_configuration *, const char *, const char *, double)")]
    public delegate* unmanaged[Cdecl]<ke_configuration*, sbyte*, sbyte*, double, double> get_double;

    [NativeTypeName("bool (*)(struct ke_configuration *, const char *, const char *, bool)")]
    public delegate* unmanaged[Cdecl]<ke_configuration*, sbyte*, sbyte*, bool, bool> get_bool;

    [NativeTypeName("const char *(*)(struct ke_configuration *, const char *, const char *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_configuration*, sbyte*, sbyte*, sbyte*, sbyte*> get_string;

    [NativeTypeName("ke_result (*)(struct ke_configuration *, const char *, const char *, int64_t)")]
    public delegate* unmanaged[Cdecl]<ke_configuration*, sbyte*, sbyte*, long, KernelEngine.Result.Native.Result> set_int;

    [NativeTypeName("ke_result (*)(struct ke_configuration *, const char *, const char *, double)")]
    public delegate* unmanaged[Cdecl]<ke_configuration*, sbyte*, sbyte*, double, KernelEngine.Result.Native.Result> set_double;

    [NativeTypeName("ke_result (*)(struct ke_configuration *, const char *, const char *, bool)")]
    public delegate* unmanaged[Cdecl]<ke_configuration*, sbyte*, sbyte*, bool, KernelEngine.Result.Native.Result> set_bool;

    [NativeTypeName("ke_result (*)(struct ke_configuration *, const char *, const char *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_configuration*, sbyte*, sbyte*, sbyte*, KernelEngine.Result.Native.Result> set_string;

    [NativeTypeName("ke_result (*)(struct ke_configuration *, const char *, ke_settings **)")]
    public delegate* unmanaged[Cdecl]<ke_configuration*, sbyte*, KernelEngine.Settings.Native.ke_settings**, KernelEngine.Result.Native.Result> section;

    [NativeTypeName("ke_result (*)(struct ke_configuration *, const char *, ke_configuration_child_func, void *)")]
    public delegate* unmanaged[Cdecl]<ke_configuration*, sbyte*, delegate* unmanaged[Cdecl]<sbyte*, void*, void>, void*, KernelEngine.Result.Native.Result> for_each_child;
}
