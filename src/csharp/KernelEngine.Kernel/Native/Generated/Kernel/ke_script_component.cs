namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_script_component
{
    [NativeTypeName("uint8_t")]
    public byte state;

    [NativeTypeName("ke_script_func")]
    public delegate* unmanaged[Cdecl]<ulong, ke_result> on_awake;

    [NativeTypeName("ke_script_func")]
    public delegate* unmanaged[Cdecl]<ulong, ke_result> on_start;

    [NativeTypeName("ke_script_update_func")]
    public delegate* unmanaged[Cdecl]<ulong, float, ke_result> on_update;

    [NativeTypeName("ke_script_update_func")]
    public delegate* unmanaged[Cdecl]<ulong, float, ke_result> on_late_update;

    [NativeTypeName("ke_script_func")]
    public delegate* unmanaged[Cdecl]<ulong, ke_result> on_destroy;

    [NativeTypeName("ke_script_input_func")]
    public delegate* unmanaged[Cdecl]<ulong, ke_input_snapshot*, ke_result> on_input;
}
