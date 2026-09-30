using KernelEngine.Common.Native;

namespace KernelEngine.Physics.Native;

public unsafe partial struct ke_physics_body2d_module_handle
{
    public ke_physics_body2d_module* @ref;

    [NativeTypeName("void (*)(ke_physics_body2d_module *)")]
    public delegate* unmanaged[Cdecl]<ke_physics_body2d_module*, void> destroy;
}
