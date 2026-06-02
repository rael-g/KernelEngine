using System.Runtime.InteropServices;

namespace KernelEngine.Framework.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_node_type_registry_create", ExactSpelling = true)]
    public static extern ke_result node_type_registry_create(ke_allocator* alloc, ke_node_type_registry** out_registry);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_resource_cache_create", ExactSpelling = true)]
    public static extern ke_result resource_cache_create(ke_allocator* alloc, ke_resource_cache** out_cache);

    [NativeTypeName("#define KE_RESOURCE_HANDLE_NONE UINT32_MAX")]
    public const uint KE_RESOURCE_HANDLE_NONE = 0xffffffffU;

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_scene_tree_create", ExactSpelling = true)]
    public static extern ke_result scene_tree_create([NativeTypeName("struct ke_world *")] ke_world* world, ke_allocator* alloc, ke_scene_tree** out_tree);
}
