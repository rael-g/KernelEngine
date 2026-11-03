using System.Numerics;

using global::KernelEngine.Ecs;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Ecs.Native;

public unsafe partial struct ke_ecs_handle
{
    public ke_ecs* @ref;

    [NativeTypeName("void (*)(ke_ecs *)")]
    public delegate* unmanaged[Cdecl]<ke_ecs*, void> destroy;
}
