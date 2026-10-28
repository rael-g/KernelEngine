using System.Runtime.InteropServices;

using KernelEngine.Asset.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Framework.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_scene", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_scene_components_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.ke_result render_scene_components_create([NativeTypeName("ke_scene_component_set *")] KernelEngine.Framework.Native.ke_scene_component_set* set);

    [DllImport("ke_render_scene", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_scene_resolve_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.ke_result render_scene_resolve_create([NativeTypeName("const ke_render_scene_resolve_params *")] ke_render_scene_resolve_params* @params, ke_render_scene_resolve_handle* out_resolve);

    [DllImport("ke_render_scene", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_label_resolve_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.ke_result render_label_resolve_create([NativeTypeName("const ke_render_label_resolve_params *")] ke_render_label_resolve_params* @params, ke_render_label_resolve_handle* out_resolve);

    [DllImport("ke_render_scene", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_scene_set_log_callback", ExactSpelling = true)]
    public static extern void render_scene_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, KernelEngine.Logger.Native.ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
