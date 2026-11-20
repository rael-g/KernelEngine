using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Ecs;
using global::KernelEngine.Input;
using global::KernelEngine.Logger;

using KernelEngine.Asset.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Input.Native;
using KernelEngine.Io.Native;
using KernelEngine.Part.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Schedule.Native;
using KernelEngine.Settings.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Framework.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_scene_tree_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result scene_tree_create([NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* ecs, ke_scene_tree_handle* out_tree);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_input_actions_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result input_actions_create([NativeTypeName("ke_settings *")] KernelEngine.Settings.Native.ke_settings* settings, ke_input_actions_handle* out_actions);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_input_actions_evaluation_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result input_actions_evaluation_create(ke_input_actions* actions, [NativeTypeName("ke_input *")] KernelEngine.Input.Native.ke_input* input, [NativeTypeName("ke_schedule *")] KernelEngine.Schedule.Native.ke_schedule* pre_update, [NativeTypeName("ke_schedule_set_id")] uint pre_update_set, [NativeTypeName("ke_owner *")] KernelEngine.Part.Native.ke_owner* out_module);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_scene_hierarchy_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result scene_hierarchy_create([NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* ecs, [NativeTypeName("ke_schedule *")] KernelEngine.Schedule.Native.ke_schedule* post_update, [NativeTypeName("ke_schedule_set_id")] uint post_update_set, [NativeTypeName("ke_owner *")] KernelEngine.Part.Native.ke_owner* out_module);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_asset_resolver_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result asset_resolver_create([NativeTypeName("ke_image_loader *")] KernelEngine.Asset.Native.ke_image_loader* image_loader, [NativeTypeName("ke_font_loader *")] KernelEngine.Text.Native.ke_font_loader* font_loader, [NativeTypeName("ke_io *")] KernelEngine.Io.Native.ke_io* io, [NativeTypeName("ke_asset_resolver_handle *")] KernelEngine.Asset.Native.ke_asset_resolver_handle* out_resolver);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_assets_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result render_assets_create([NativeTypeName("ke_asset_resolver *")] KernelEngine.Asset.Native.ke_asset_resolver* resolver, [NativeTypeName("ke_render_service *")] KernelEngine.Render.Native.ke_render_service* service, [NativeTypeName("ke_render_assets_handle *")] KernelEngine.Render.Native.ke_render_assets_handle* out_assets);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_framework_set_log_callback", ExactSpelling = true)]
    public static extern void framework_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_framework_parts", ExactSpelling = true)]
    [return: NativeTypeName("const ke_part *")]
    public static extern KernelEngine.Part.Native.ke_part* framework_parts([NativeTypeName("size_t *")] nuint* out_count);
}
