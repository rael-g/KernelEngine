using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_module", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_shadow_create", ExactSpelling = true)]
    public static extern ke_render_shadow_handle render_shadow_create([NativeTypeName("ke_runtime *")] KernelEngine.Runtime.Native.ke_runtime* runtime, [NativeTypeName("ke_render_service *")] KernelEngine.Render.Native.ke_render_service* core, [NativeTypeName("ke_gpu_device *")] KernelEngine.Render.Native.ke_gpu_device* device, [NativeTypeName("ke_ndc_convention")] KernelEngine.View.Native.ke_ndc_convention ndc, [NativeTypeName("ke_view_space *")] KernelEngine.View.Native.ke_view_space* view_space, [NativeTypeName("ke_bool")] byte enabled, [NativeTypeName("ke_component_id")] uint mesh_cid, [NativeTypeName("ke_component_id")] uint world_transform_cid, [NativeTypeName("ke_component_id")] uint light_cid, [NativeTypeName("ke_component_id")] uint frame_cid, [NativeTypeName("const ke_render_shadow_params *")] ke_render_shadow_params* @params, [NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);

    [DllImport("ke_render_module", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_ui_create", ExactSpelling = true)]
    public static extern ke_render_ui_handle render_ui_create([NativeTypeName("ke_runtime *")] KernelEngine.Runtime.Native.ke_runtime* runtime, [NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* ecs, [NativeTypeName("ke_render_service *")] KernelEngine.Render.Native.ke_render_service* core, [NativeTypeName("ke_gpu_device *")] KernelEngine.Render.Native.ke_gpu_device* device, [NativeTypeName("ke_ndc_convention")] KernelEngine.View.Native.ke_ndc_convention ndc, [NativeTypeName("ke_component_id")] uint bb_cid, [NativeTypeName("uint32_t")] uint cmd_slot, [NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);

    [DllImport("ke_render_module", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_module_create", ExactSpelling = true)]
    public static extern ke_render_module_handle render_module_create([NativeTypeName("ke_runtime *")] KernelEngine.Runtime.Native.ke_runtime* runtime, [NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* ecs, [NativeTypeName("ke_gpu_device *")] KernelEngine.Render.Native.ke_gpu_device* device, [NativeTypeName("ke_gpu_render_target *")] KernelEngine.Render.Native.ke_gpu_render_target* target, [NativeTypeName("ke_world *")] KernelEngine.Framework.Native.ke_world* world, [NativeTypeName("ke_bool")] byte default_passes, [NativeTypeName("struct ke_logger *")] KernelEngine.Logger.Native.ke_logger* logger, [NativeTypeName("ke_asset_resolver *")] KernelEngine.Asset.Native.ke_asset_resolver* asset_resolver, [NativeTypeName("const ke_render_cluster_params *")] ke_render_cluster_params* cluster_params, [NativeTypeName("const ke_render_feature_params *")] ke_render_feature_params* feature_params, [NativeTypeName("const ke_render_shadow_params *")] ke_render_shadow_params* shadow_params, [NativeTypeName("ke_view_space *")] KernelEngine.View.Native.ke_view_space* view_space, [NativeTypeName("const char *")] sbyte* shader_dir, [NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);

    [DllImport("ke_render_module", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_register_scene_apply", ExactSpelling = true)]
    public static extern bool render_register_scene_apply([NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* ecs, [NativeTypeName("ke_world *")] KernelEngine.Framework.Native.ke_world* world);

    [DllImport("ke_render_module", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_module_core", ExactSpelling = true)]
    [return: NativeTypeName("ke_render_service *")]
    public static extern KernelEngine.Render.Native.ke_render_service* render_module_core(ke_render_module* module);

    [DllImport("ke_render_module", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_module_load_font", ExactSpelling = true)]
    [return: NativeTypeName("ke_ui_font_handle")]
    public static extern KernelEngine.Render.Native.ke_ui_font_handle render_module_load_font(ke_render_module* module, [NativeTypeName("const char *")] sbyte* key, [NativeTypeName("ke_texture_handle")] KernelEngine.Render.Native.ke_texture_handle atlas, [NativeTypeName("const ke_glyph_metrics *")] KernelEngine.Text.Native.ke_glyph_metrics* glyphs, [NativeTypeName("uint32_t")] uint glyph_count, float line_height, float ascent, [NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);
}
