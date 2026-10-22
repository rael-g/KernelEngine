using System.Runtime.InteropServices;

using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_scene", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_scene_components_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_scene_component_set_handle")]
    public static extern KernelEngine.Framework.Native.ke_scene_component_set_handle render_scene_components_create();

    [DllImport("ke_render_scene", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_scene_resolve_create", ExactSpelling = true)]
    public static extern ke_render_scene_resolve_handle render_scene_resolve_create([NativeTypeName("const ke_render_scene_resolve_params *")] ke_render_scene_resolve_params* @params, [NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);

    [DllImport("ke_render_scene", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_label_resolve_create", ExactSpelling = true)]
    public static extern ke_render_label_resolve_handle render_label_resolve_create([NativeTypeName("const ke_render_label_resolve_params *")] ke_render_label_resolve_params* @params, [NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);

    [DllImport("ke_render_scene", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_scene_set_log_callback", ExactSpelling = true)]
    public static extern void render_scene_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
