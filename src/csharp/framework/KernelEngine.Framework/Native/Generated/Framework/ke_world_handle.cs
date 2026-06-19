using KernelEngine.Common.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_world_handle
{
    public ke_world* @ref;

    [NativeTypeName("void (*)(ke_world *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, void> destroy;
}
