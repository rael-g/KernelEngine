using KernelEngine.Common.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_scene_tree
{
    public void* handle;

    [NativeTypeName("ke_entity (*)(struct ke_scene_tree *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, ulong> root;

    [NativeTypeName("ke_entity (*)(struct ke_scene_tree *, const char *, ke_entity, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, sbyte*, ulong, KernelEngine.Common.Native.ke_error**, ulong> create_node;

    [NativeTypeName("ke_entity (*)(struct ke_scene_tree *, const char *, ke_entity, ke_ecs_commands *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, sbyte*, ulong, KernelEngine.Ecs.Native.ke_ecs_commands*, KernelEngine.Common.Native.ke_error**, ulong> create_node_deferred;

    [NativeTypeName("bool (*)(struct ke_scene_tree *, ke_entity, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, ulong, KernelEngine.Common.Native.ke_error**, bool> destroy_node;

    [NativeTypeName("bool (*)(struct ke_scene_tree *, ke_entity, ke_ecs_commands *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, ulong, KernelEngine.Ecs.Native.ke_ecs_commands*, KernelEngine.Common.Native.ke_error**, bool> destroy_node_deferred;

    [NativeTypeName("void (*)(struct ke_scene_tree *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, void> destroy_all;

    [NativeTypeName("ke_entity (*)(struct ke_scene_tree *, const char *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, sbyte*, KernelEngine.Common.Native.ke_error**, ulong> find_node;

    [NativeTypeName("ke_entity (*)(struct ke_scene_tree *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, ulong, ulong> parent;

    [NativeTypeName("ke_entity (*)(struct ke_scene_tree *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, ulong, ulong> first_child;

    [NativeTypeName("ke_entity (*)(struct ke_scene_tree *, ke_entity)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, ulong, ulong> next_sibling;

    [NativeTypeName("void (*)(struct ke_scene_tree *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, void> propagate_transforms;
}
