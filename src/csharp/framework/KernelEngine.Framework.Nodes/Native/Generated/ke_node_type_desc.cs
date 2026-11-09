using System.Numerics;

using global::KernelEngine.Common;
using global::KernelEngine.Ecs;
using global::KernelEngine.Physics;
using global::KernelEngine.Render;

using KernelEngine.Asset.Native;
using KernelEngine.Audio.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Framework.Native;
using KernelEngine.Io.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Framework.Nodes.Native;

public unsafe partial struct ke_node_type_desc
{
    [NativeTypeName("const char *")]
    public sbyte* name;

    [NativeTypeName("size_t")]
    public nuint fields_size;

    [NativeTypeName("size_t")]
    public nuint fields_alignment;

    [NativeTypeName("const ke_component_field *")]
    public KernelEngine.Ecs.Native.ke_component_field* fields;

    [NativeTypeName("uint32_t")]
    public uint field_count;

    [NativeTypeName("const void *")]
    public void* initial;

    [NativeTypeName("size_t")]
    public nuint initial_size;

    [NativeTypeName("const ke_node_with *")]
    public ke_node_with* with;

    [NativeTypeName("uint32_t")]
    public uint with_count;

    [NativeTypeName("ke_node_behaviour_fn")]
    public delegate* unmanaged[Cdecl]<ke_node_ctx*, void*, KernelEngine.Result.Native.Result> ready;

    [NativeTypeName("ke_node_behaviour_fn")]
    public delegate* unmanaged[Cdecl]<ke_node_ctx*, void*, KernelEngine.Result.Native.Result> update;

    [NativeTypeName("ke_node_behaviour_fn")]
    public delegate* unmanaged[Cdecl]<ke_node_ctx*, void*, KernelEngine.Result.Native.Result> fixed_update;

    [NativeTypeName("const ke_component_id *")]
    public global::KernelEngine.Ecs.ComponentId* events;

    [NativeTypeName("uint32_t")]
    public uint event_count;

    [NativeTypeName("ke_node_behaviour_fn")]
    public delegate* unmanaged[Cdecl]<ke_node_ctx*, void*, KernelEngine.Result.Native.Result> on;

    public void* user_data;
}
