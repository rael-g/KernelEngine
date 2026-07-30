using KernelEngine.Common.Native;

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

    [NativeTypeName("bool (*)(struct ke_configuration *, const char *, const char *, int64_t, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_configuration*, sbyte*, sbyte*, long, ke_error**, bool> set_int;

    [NativeTypeName("bool (*)(struct ke_configuration *, const char *, const char *, double, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_configuration*, sbyte*, sbyte*, double, ke_error**, bool> set_double;

    [NativeTypeName("bool (*)(struct ke_configuration *, const char *, const char *, bool, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_configuration*, sbyte*, sbyte*, bool, ke_error**, bool> set_bool;

    [NativeTypeName("bool (*)(struct ke_configuration *, const char *, const char *, const char *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_configuration*, sbyte*, sbyte*, sbyte*, ke_error**, bool> set_string;

    [NativeTypeName("ke_configuration_subscription (*)(struct ke_configuration *, const char *, ke_configuration_change_func, void *)")]
    public delegate* unmanaged[Cdecl]<ke_configuration*, sbyte*, delegate* unmanaged[Cdecl]<sbyte*, void*, void>, void*, uint> subscribe;

    [NativeTypeName("void (*)(struct ke_configuration *, ke_configuration_subscription)")]
    public delegate* unmanaged[Cdecl]<ke_configuration*, uint, void> unsubscribe;
}
