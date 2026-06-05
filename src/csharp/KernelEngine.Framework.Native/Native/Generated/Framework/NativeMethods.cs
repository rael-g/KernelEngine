using System;
using System.Runtime.InteropServices;

namespace KernelEngine.Framework.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_node_type_registry_create", ExactSpelling = true)]
    public static extern ke_result node_type_registry_create(ke_allocator* alloc, ke_node_type_registry** out_registry);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_scene_loader_create", ExactSpelling = true)]
    public static extern ke_result scene_loader_create(ke_allocator* alloc, [NativeTypeName("struct ke_world *")] ke_world* world, ke_scene_tree* tree, ke_node_type_registry* registry, [NativeTypeName("const char *")] sbyte* project_root, ke_scene_loader** out_loader);

    [NativeTypeName("#define KE_SCENE_PROPERTIES_COMPONENT_NAME \"scene_properties\"")]
    public static ReadOnlySpan<byte> KE_SCENE_PROPERTIES_COMPONENT_NAME => "scene_properties"u8;

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_input_actions_create", ExactSpelling = true)]
    public static extern ke_result input_actions_create(ke_allocator* alloc, ke_input_actions** out_actions);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_resource_cache_create", ExactSpelling = true)]
    public static extern ke_result resource_cache_create(ke_allocator* alloc, ke_resource_cache** out_cache);

    [NativeTypeName("#define KE_RESOURCE_HANDLE_NONE UINT32_MAX")]
    public const uint KE_RESOURCE_HANDLE_NONE = 0xffffffffU;

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_scene_tree_create", ExactSpelling = true)]
    public static extern ke_result scene_tree_create([NativeTypeName("struct ke_world *")] ke_world* world, ke_allocator* alloc, ke_scene_tree** out_tree);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_mesh_shape_bake", ExactSpelling = true)]
    public static extern ke_result mesh_shape_bake(ke_allocator* alloc, ke_mesh_primitive prim, [NativeTypeName("uint32_t")] uint segments, ke_mesh_shape_data* out_data);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_mesh_shape_free", ExactSpelling = true)]
    public static extern void mesh_shape_free(ke_allocator* alloc, ke_mesh_shape_data* data);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_material_file_parse", ExactSpelling = true)]
    public static extern ke_result material_file_parse([NativeTypeName("const char *")] sbyte* path, ke_material_spec* out_spec);

    [NativeTypeName("#define KE_MATERIAL_PATH_MAX 256")]
    public const int KE_MATERIAL_PATH_MAX = 256;

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_asset_resolver_create", ExactSpelling = true)]
    public static extern ke_result asset_resolver_create(ke_allocator* alloc, ke_image_loader* image_loader, [NativeTypeName("const char *")] sbyte* project_root, ke_asset_resolver** @out);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_resource_future_wait", ExactSpelling = true)]
    public static extern ke_result resource_future_wait(ke_resource_future* future, [NativeTypeName("uint32_t")] uint timeout_ms);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_resource_future_get_handle", ExactSpelling = true)]
    [return: NativeTypeName("uint32_t")]
    public static extern uint resource_future_get_handle(ke_resource_future* future);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_resource_future_release", ExactSpelling = true)]
    public static extern void resource_future_release(ke_resource_future* future);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_resource_queue_create", ExactSpelling = true)]
    public static extern ke_result resource_queue_create(ke_allocator* alloc, ke_resource_queue** @out);
}
