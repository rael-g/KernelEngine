namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_input_actions_handle
{
    public ke_input_actions* @ref;

    [NativeTypeName("void (*)(ke_input_actions *)")]
    public delegate* unmanaged[Cdecl]<ke_input_actions*, void> destroy;
}
