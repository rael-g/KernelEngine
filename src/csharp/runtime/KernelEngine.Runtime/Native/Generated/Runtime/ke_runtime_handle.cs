using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Runtime;

using KernelEngine.Ecs.Native;
using KernelEngine.Result.Native;
using KernelEngine.TaskPool.Native;

namespace KernelEngine.Runtime.Native;

public unsafe partial struct ke_runtime_handle
{
    public ke_runtime* @ref;

    [NativeTypeName("void (*)(ke_runtime *)")]
    public delegate* unmanaged[Cdecl]<ke_runtime*, void> destroy;
}
