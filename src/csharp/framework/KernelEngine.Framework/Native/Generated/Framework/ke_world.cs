using KernelEngine.Asset.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Input.Native;
using KernelEngine.Io.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

public unsafe partial struct ke_world
{
    public void* handle;

    [NativeTypeName("ke_ecs *(*)(struct ke_world *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, KernelEngine.Ecs.Native.ke_ecs*> ecs;

    [NativeTypeName("ke_runtime *(*)(struct ke_world *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, KernelEngine.Runtime.Native.ke_runtime*> runtime;

    [NativeTypeName("struct ke_scene_tree *(*)(struct ke_world *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, ke_scene_tree*> scene_tree;

    [NativeTypeName("ke_result (*)(struct ke_world *, ke_component_id, const ke_component_field *, uint32_t)")]
    public delegate* unmanaged[Cdecl]<ke_world*, uint, KernelEngine.Ecs.Native.ke_component_field*, uint, KernelEngine.Result.Native.ke_result> register_component_fields;

    [NativeTypeName("const ke_component_field *(*)(struct ke_world *, ke_component_id, uint32_t *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, uint, uint*, KernelEngine.Ecs.Native.ke_component_field*> get_component_fields;

    [NativeTypeName("ke_result (*)(struct ke_world *, ke_component_id, ke_component_apply_fn, void *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, uint, delegate* unmanaged[Cdecl]<void*, void*, KernelEngine.Ecs.Native.ke_variant_table_entry*, uint, KernelEngine.Result.Native.ke_result>, void*, KernelEngine.Result.Native.ke_result> register_component_apply;

    [NativeTypeName("ke_component_apply_fn (*)(struct ke_world *, ke_component_id, void **)")]
    public delegate* unmanaged[Cdecl]<ke_world*, uint, void**, delegate* unmanaged[Cdecl]<void*, void*, KernelEngine.Ecs.Native.ke_variant_table_entry*, uint, KernelEngine.Result.Native.ke_result>> get_component_apply;

    [NativeTypeName("ke_result (*)(struct ke_world *, const char *, const char *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, sbyte*, sbyte*, KernelEngine.Result.Native.ke_result> register_component_alias;

    [NativeTypeName("ke_result (*)(struct ke_world *, const char *, ke_component_meta *)")]
    public delegate* unmanaged[Cdecl]<ke_world*, sbyte*, KernelEngine.Ecs.Native.ke_component_meta*, KernelEngine.Result.Native.ke_result> resolve_component;
}
