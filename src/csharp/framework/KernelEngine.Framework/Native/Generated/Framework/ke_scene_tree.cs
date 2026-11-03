using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Input;
using global::KernelEngine.Logger;

using KernelEngine.Asset.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Io.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_scene_tree
{
    public void* handle;

    [NativeTypeName("ke_entity (*)(struct ke_scene_tree *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, global::KernelEngine.Ecs.Entity> root;

    [NativeTypeName("ke_result (*)(struct ke_scene_tree *, const char *, ke_entity, ke_entity *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, sbyte*, global::KernelEngine.Ecs.Entity, global::KernelEngine.Ecs.Entity*, KernelEngine.Result.Native.Result> create_node;

    [NativeTypeName("ke_result (*)(struct ke_scene_tree *, const char *, ke_entity, ke_ecs_commands *, ke_entity *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, sbyte*, global::KernelEngine.Ecs.Entity, KernelEngine.Ecs.Native.ke_ecs_commands*, global::KernelEngine.Ecs.Entity*, KernelEngine.Result.Native.Result> create_node_deferred;

    [NativeTypeName("ke_result (*)(struct ke_scene_tree *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, global::KernelEngine.Ecs.Entity, KernelEngine.Result.Native.Result> destroy_node;

    [NativeTypeName("ke_result (*)(struct ke_scene_tree *, ke_entity, ke_ecs_commands *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, global::KernelEngine.Ecs.Entity, KernelEngine.Ecs.Native.ke_ecs_commands*, KernelEngine.Result.Native.Result> destroy_node_deferred;

    [NativeTypeName("ke_result (*)(struct ke_scene_tree *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, KernelEngine.Result.Native.Result> destroy_all;

    [NativeTypeName("ke_entity (*)(struct ke_scene_tree *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, sbyte*, global::KernelEngine.Ecs.Entity> find_node;

    [NativeTypeName("ke_entity (*)(struct ke_scene_tree *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, global::KernelEngine.Ecs.Entity, global::KernelEngine.Ecs.Entity> parent;

    [NativeTypeName("ke_entity (*)(struct ke_scene_tree *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, global::KernelEngine.Ecs.Entity, global::KernelEngine.Ecs.Entity> first_child;

    [NativeTypeName("ke_entity (*)(struct ke_scene_tree *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, global::KernelEngine.Ecs.Entity, global::KernelEngine.Ecs.Entity> next_sibling;

    [NativeTypeName("void (*)(struct ke_scene_tree *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, void> propagate_transforms;

    [NativeTypeName("uint64_t (*)(struct ke_scene_tree *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, ulong> hierarchy_generation;
}
