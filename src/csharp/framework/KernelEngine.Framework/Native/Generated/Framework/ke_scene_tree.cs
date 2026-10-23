using KernelEngine.Asset.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Input.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_scene_tree
{
    public void* handle;

    [NativeTypeName("ke_entity (*)(struct ke_scene_tree *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, ulong> root;

    [NativeTypeName("ke_result (*)(struct ke_scene_tree *, const char *, ke_entity, ke_entity *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, sbyte*, ulong, ulong*, KernelEngine.Result.Native.ke_result> create_node;

    [NativeTypeName("ke_result (*)(struct ke_scene_tree *, const char *, ke_entity, ke_ecs_commands *, ke_entity *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, sbyte*, ulong, KernelEngine.Ecs.Native.ke_ecs_commands*, ulong*, KernelEngine.Result.Native.ke_result> create_node_deferred;

    [NativeTypeName("ke_result (*)(struct ke_scene_tree *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, ulong, KernelEngine.Result.Native.ke_result> destroy_node;

    [NativeTypeName("ke_result (*)(struct ke_scene_tree *, ke_entity, ke_ecs_commands *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, ulong, KernelEngine.Ecs.Native.ke_ecs_commands*, KernelEngine.Result.Native.ke_result> destroy_node_deferred;

    [NativeTypeName("void (*)(struct ke_scene_tree *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, void> destroy_all;

    [NativeTypeName("ke_entity (*)(struct ke_scene_tree *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, sbyte*, ulong> find_node;

    [NativeTypeName("ke_entity (*)(struct ke_scene_tree *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, ulong, ulong> parent;

    [NativeTypeName("ke_entity (*)(struct ke_scene_tree *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, ulong, ulong> first_child;

    [NativeTypeName("ke_entity (*)(struct ke_scene_tree *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, ulong, ulong> next_sibling;

    [NativeTypeName("void (*)(struct ke_scene_tree *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, void> propagate_transforms;

    [NativeTypeName("uint64_t (*)(struct ke_scene_tree *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, ulong> hierarchy_generation;
}
