using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.RenderGraph;

using KernelEngine.Ecs.Native;
using KernelEngine.Module.Native;
using KernelEngine.Render.Frame.Native;
using KernelEngine.Render.Native;
using KernelEngine.RenderGraph.Native;
using KernelEngine.Result.Native;
using KernelEngine.Settings.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_frame", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_frame_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result render_frame_create([NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* ecs, [NativeTypeName("ke_render_graph *")] KernelEngine.RenderGraph.Native.ke_render_graph* graph, [NativeTypeName("ke_render_service *")] KernelEngine.Render.Native.ke_render_service* service, [NativeTypeName("ke_render_camera *")] KernelEngine.Render.Native.ke_render_camera* camera, [NativeTypeName("ke_render_scene_resolve *")] KernelEngine.Render.Native.ke_render_scene_resolve* scene, [NativeTypeName("ke_settings *")] KernelEngine.Settings.Native.ke_settings* settings, [NativeTypeName("ke_render_frame_handle *")] KernelEngine.Render.Frame.Native.ke_render_frame_handle* out_frame);

    [DllImport("ke_render_frame", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_frame_systems_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result render_frame_systems_create([NativeTypeName("ke_render_frame *")] KernelEngine.Render.Frame.Native.ke_render_frame* frame, [NativeTypeName("ke_module_handle *")] KernelEngine.Module.Native.ke_module_handle* out_module);

    [DllImport("ke_render_frame", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_frame_set_log_callback", ExactSpelling = true)]
    public static extern void render_frame_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
