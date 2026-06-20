using KernelEngine.Common.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_scene_tree
{
    public void* handle;

    [NativeTypeName("ke_entity (*)(struct ke_scene_tree *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, ulong> root;

    [NativeTypeName("ke_entity (*)(struct ke_scene_tree *, const char *, ke_entity, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, sbyte*, ulong, ke_error**, ulong> create_node;

    [NativeTypeName("bool (*)(struct ke_scene_tree *, ke_entity, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, ulong, ke_error**, bool> destroy_node;

    [NativeTypeName("void (*)(struct ke_scene_tree *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, void> destroy_all;

    [NativeTypeName("ke_entity (*)(struct ke_scene_tree *, const char *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, sbyte*, ke_error**, ulong> find_node;

    [NativeTypeName("void (*)(struct ke_scene_tree *)")]
    public delegate* unmanaged[Cdecl]<ke_scene_tree*, void> propagate_transforms;
}
