using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Framework.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_world_create", ExactSpelling = true)]
    public static extern ke_result world_create([NativeTypeName("const ke_world_params *")] ke_world_params* @params, ke_world_handle* out_world, ke_error** out_error);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_scene_tree_create", ExactSpelling = true)]
    public static extern ke_result scene_tree_create([NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* ecs, ke_scene_tree_handle* out_tree, ke_error** out_error);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_scene_loader_create", ExactSpelling = true)]
    public static extern ke_result scene_loader_create([NativeTypeName("struct ke_world *")] ke_world* world, [NativeTypeName("const char *")] sbyte* project_root, ke_scene_loader_handle* out_loader, ke_error** out_error);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_input_actions_create", ExactSpelling = true)]
    public static extern ke_result input_actions_create(ke_input_actions_handle* out_actions, ke_error** out_error);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_asset_resolver_create", ExactSpelling = true)]
    public static extern ke_result asset_resolver_create([NativeTypeName("ke_image_loader *")] KernelEngine.Asset.Native.ke_image_loader* image_loader, [NativeTypeName("ke_font_loader *")] KernelEngine.Text.Native.ke_font_loader* font_loader, [NativeTypeName("const char *")] sbyte* project_root, [NativeTypeName("ke_asset_resolver_handle *")] KernelEngine.Asset.Native.ke_asset_resolver_handle* @out, ke_error** out_error);
}
