using KernelEngine.Common.Native;

namespace KernelEngine.Ecs.Native;

public unsafe partial struct ke_ecs_handle
{
    public ke_ecs* @ref;

    [NativeTypeName("void (*)(ke_ecs *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, void> destroy;
}
