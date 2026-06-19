using KernelEngine.Common.Native;

namespace KernelEngine.Physics.Native;

public unsafe partial struct ke_physics_2d_handle
{
    public ke_physics_2d* @ref;

    [NativeTypeName("void (*)(ke_physics_2d *)")]
    public delegate* unmanaged[Cdecl]<ke_physics_2d*, void> destroy;
}
