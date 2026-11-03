using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Runtime;

using KernelEngine.Ecs.Native;
using KernelEngine.Result.Native;
using KernelEngine.TaskPool.Native;

namespace KernelEngine.Runtime.Native;

public unsafe partial struct ke_query_decl
{
    [NativeTypeName("const ke_component_access *")]
    public global::KernelEngine.Runtime.ComponentAccess* terms;

    [NativeTypeName("uint32_t")]
    public uint term_count;
}
