using KernelEngine.Common.Native;

namespace KernelEngine.Input.Native;

public unsafe partial struct ke_input_handle
{
    public ke_input* @ref;

    [NativeTypeName("void (*)(ke_input *)")]
    public delegate* unmanaged[Cdecl]<ke_input*, void> destroy;
}
