using System.Numerics;

using global::KernelEngine.Logger;
using global::KernelEngine.Part;

using KernelEngine.Completion.Native;
using KernelEngine.Result.Native;
using KernelEngine.Settings.Native;

namespace KernelEngine.Part.Native;

public unsafe partial struct ke_part
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    [NativeTypeName("const char *const *")]
    public sbyte** provides;

    [NativeTypeName("size_t")]
    public nuint provides_count;

    [NativeTypeName("const ke_part_slot *")]
    public ke_part_slot* slots;

    [NativeTypeName("size_t")]
    public nuint slot_count;

    [NativeTypeName("ke_result (*)(const struct ke_part *, const ke_part_bound *, ke_settings *, ke_owner *)")]
    public delegate* unmanaged[Cdecl]<ke_part*, ke_part_bound*, KernelEngine.Settings.Native.ke_settings*, ke_owner*, KernelEngine.Result.Native.Result> create;

    [NativeTypeName("void *(*)(void *, size_t)")]
    public delegate* unmanaged[Cdecl]<void*, nuint, void*> provided;

    [NativeTypeName("ke_result (*)(void *, ke_completion **)")]
    public delegate* unmanaged[Cdecl]<void*, KernelEngine.Completion.Native.ke_completion**, KernelEngine.Result.Native.Result> ready;

    [NativeTypeName("void (*)(void *)")]
    public delegate* unmanaged[Cdecl]<void*, void> pump;

    [NativeTypeName("void (*)(ke_log_callback, void *)")]
    public delegate* unmanaged[Cdecl]<delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void>, void*, void> set_log;
}
