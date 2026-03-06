namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_script_component
{
    public bool started;

    [NativeTypeName("ke_result (*)(uint64_t)")]
    public delegate* unmanaged[Cdecl]<ulong, ke_result> on_start;

    [NativeTypeName("ke_result (*)(uint64_t, float)")]
    public delegate* unmanaged[Cdecl]<ulong, float, ke_result> on_update;
}
