using System.Numerics;

using KernelEngine.Result.Native;

namespace KernelEngine.Settings.Native;

public unsafe partial struct ke_settings
{
    public void* handle;

    [NativeTypeName("ke_result (*)(ke_settings *, const char *, bool *)")]
    public delegate* unmanaged[Cdecl]<ke_settings*, sbyte*, bool*, KernelEngine.Result.Native.Result> get_bool;

    [NativeTypeName("ke_result (*)(ke_settings *, const char *, int64_t *)")]
    public delegate* unmanaged[Cdecl]<ke_settings*, sbyte*, long*, KernelEngine.Result.Native.Result> get_int;

    [NativeTypeName("ke_result (*)(ke_settings *, const char *, double *)")]
    public delegate* unmanaged[Cdecl]<ke_settings*, sbyte*, double*, KernelEngine.Result.Native.Result> get_double;

    [NativeTypeName("ke_result (*)(ke_settings *, const char *, const char **)")]
    public delegate* unmanaged[Cdecl]<ke_settings*, sbyte*, sbyte**, KernelEngine.Result.Native.Result> get_string;

    [NativeTypeName("ke_result (*)(ke_settings *, ke_settings_key_func, void *)")]
    public delegate* unmanaged[Cdecl]<ke_settings*, delegate* unmanaged[Cdecl]<sbyte*, void*, void>, void*, KernelEngine.Result.Native.Result> for_each_key;
}
