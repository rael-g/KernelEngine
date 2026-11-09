using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Ecs;
using global::KernelEngine.Input;
using global::KernelEngine.Logger;

using KernelEngine.Asset.Native;
using KernelEngine.Configuration.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Input.Native;
using KernelEngine.Io.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_scene_tree_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result scene_tree_create([NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* ecs, [NativeTypeName("ke_runtime *")] KernelEngine.Runtime.Native.ke_runtime* runtime, ke_scene_tree_handle* out_tree);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_input_actions_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result input_actions_create([NativeTypeName("ke_runtime *")] KernelEngine.Runtime.Native.ke_runtime* runtime, [NativeTypeName("ke_input *")] KernelEngine.Input.Native.ke_input* input, [NativeTypeName("ke_configuration *")] KernelEngine.Configuration.Native.ke_configuration* configuration, [NativeTypeName("const ke_input_actions_config *")] InputActionsConfig* config, ke_input_actions_handle* out_actions);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_asset_resolver_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result asset_resolver_create([NativeTypeName("ke_image_loader *")] KernelEngine.Asset.Native.ke_image_loader* image_loader, [NativeTypeName("ke_font_loader *")] KernelEngine.Text.Native.ke_font_loader* font_loader, [NativeTypeName("const char *")] sbyte* project_root, [NativeTypeName("ke_io *")] KernelEngine.Io.Native.ke_io* io, [NativeTypeName("ke_asset_resolver_handle *")] KernelEngine.Asset.Native.ke_asset_resolver_handle* out_resolver);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_framework_set_log_callback", ExactSpelling = true)]
    public static extern void framework_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
