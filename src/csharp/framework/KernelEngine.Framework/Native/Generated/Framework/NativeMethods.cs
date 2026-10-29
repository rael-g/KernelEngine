using System.Runtime.InteropServices;

using KernelEngine.Asset.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Input.Native;
using KernelEngine.Io.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_scene_component_set_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.ke_result scene_component_set_create(ke_scene_component_set_handle* out_set);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_world_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.ke_result world_create([NativeTypeName("const ke_world_params *")] ke_world_params* @params, ke_world_handle* out_world);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_scene_tree_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.ke_result scene_tree_create([NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* ecs, [NativeTypeName("ke_runtime *")] KernelEngine.Runtime.Native.ke_runtime* runtime, ke_scene_tree_handle* out_tree);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_scene_loader_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.ke_result scene_loader_create([NativeTypeName("struct ke_world *")] ke_world* world, [NativeTypeName("ke_asset_resolver *")] KernelEngine.Asset.Native.ke_asset_resolver* assets, [NativeTypeName("ke_io *")] KernelEngine.Io.Native.ke_io* io, ke_scene_loader_handle* out_loader);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_input_actions_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.ke_result input_actions_create([NativeTypeName("ke_io *")] KernelEngine.Io.Native.ke_io* io, ke_input_actions_handle* out_actions);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_signal_bus_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.ke_result signal_bus_create([NativeTypeName("const ke_signal_bus_params *")] ke_signal_bus_params* @params, ke_signal_bus_handle* out_bus);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_asset_resolver_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.ke_result asset_resolver_create([NativeTypeName("ke_image_loader *")] KernelEngine.Asset.Native.ke_image_loader* image_loader, [NativeTypeName("ke_font_loader *")] KernelEngine.Text.Native.ke_font_loader* font_loader, [NativeTypeName("const char *")] sbyte* project_root, [NativeTypeName("ke_io *")] KernelEngine.Io.Native.ke_io* io, [NativeTypeName("ke_asset_resolver_handle *")] KernelEngine.Asset.Native.ke_asset_resolver_handle* out_resolver);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_script_host_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.ke_result script_host_create([NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* ecs, [NativeTypeName("const ke_script_host_params *")] ke_script_host_params* @params, ke_script_host_handle* out_host);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_framework_set_log_callback", ExactSpelling = true)]
    public static extern void framework_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, KernelEngine.Logger.Native.ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
