using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;

using KernelEngine.Ecs.Native;
using KernelEngine.Framework.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Physics.Native;

public unsafe partial struct ke_physics_body2d_module_handle
{
    public ke_physics_body2d_module* @ref;

    [NativeTypeName("void (*)(ke_physics_body2d_module *)")]
    public delegate* unmanaged[Cdecl]<ke_physics_body2d_module*, void> destroy;
}
