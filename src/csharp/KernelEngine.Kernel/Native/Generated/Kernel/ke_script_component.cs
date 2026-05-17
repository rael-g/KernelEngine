namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_script_component
{
    public bool started;

    [NativeTypeName("ke_script_func")]
    public delegate* unmanaged[Cdecl]<ulong, ke_result> on_start;

    [NativeTypeName("ke_script_update_func")]
    public delegate* unmanaged[Cdecl]<ulong, float, ke_result> on_update;
}
