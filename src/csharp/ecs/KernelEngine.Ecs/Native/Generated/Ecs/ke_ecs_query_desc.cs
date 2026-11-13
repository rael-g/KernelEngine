using System.Numerics;

using global::KernelEngine.Ecs;

using KernelEngine.Common.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Ecs.Native;

public unsafe partial struct ke_ecs_query_desc
{
    [NativeTypeName("const ke_ecs_query_term *")]
    public global::KernelEngine.Ecs.EcsQueryTerm* terms;

    [NativeTypeName("uint32_t")]
    public uint term_count;

    [NativeTypeName("const ke_component_id *")]
    public global::KernelEngine.Ecs.ComponentId* with;

    [NativeTypeName("uint32_t")]
    public uint with_count;

    [NativeTypeName("const ke_component_id *")]
    public global::KernelEngine.Ecs.ComponentId* without;

    [NativeTypeName("uint32_t")]
    public uint without_count;

    public bool track_changes;
}
