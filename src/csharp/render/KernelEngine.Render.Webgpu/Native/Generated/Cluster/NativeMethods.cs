using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Render;

using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.View.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_cluster", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_cluster_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result render_cluster_create([NativeTypeName("ke_runtime *")] KernelEngine.Runtime.Native.ke_runtime* runtime, [NativeTypeName("ke_render_service *")] KernelEngine.Render.Native.ke_render_service* service, [NativeTypeName("ke_gpu_device *")] KernelEngine.Render.Native.ke_gpu_device* device, [NativeTypeName("ke_view_space *")] KernelEngine.View.Native.ke_view_space* view_space, [NativeTypeName("ke_render_camera *")] KernelEngine.Render.Native.ke_render_camera* camera, [NativeTypeName("ke_render_scene_resolve *")] KernelEngine.Render.Native.ke_render_scene_resolve* scene, [NativeTypeName("ke_render_frame *")] KernelEngine.Render.Native.ke_render_frame* frame, [NativeTypeName("const ke_render_cluster_config *")] ke_render_cluster_config* config, [NativeTypeName("ke_render_cluster_resources *")] global::KernelEngine.Render.RenderClusterResources* out_resources, ke_render_cluster_handle* out_cluster);

    [DllImport("ke_render_cluster", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_cluster_set_log_callback", ExactSpelling = true)]
    public static extern void render_cluster_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
