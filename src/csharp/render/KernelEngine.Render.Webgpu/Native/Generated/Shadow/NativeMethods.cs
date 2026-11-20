using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.RenderGraph;

using KernelEngine.Part.Native;
using KernelEngine.Render.Frame.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Schedule.Native;
using KernelEngine.Settings.Native;
using KernelEngine.View.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_shadow", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_shadow_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result render_shadow_create([NativeTypeName("ke_render_service *")] KernelEngine.Render.Native.ke_render_service* service, [NativeTypeName("ke_gpu_device *")] KernelEngine.Render.Native.ke_gpu_device* device, [NativeTypeName("ke_render_frame *")] KernelEngine.Render.Frame.Native.ke_render_frame* frame, [NativeTypeName("ke_render_scene_resolve *")] KernelEngine.Render.Native.ke_render_scene_resolve* scene, [NativeTypeName("ke_view_space *")] KernelEngine.View.Native.ke_view_space* view_space, [NativeTypeName("ke_schedule *")] KernelEngine.Schedule.Native.ke_schedule* render_prepare, [NativeTypeName("ke_schedule_set_id")] uint render_prepare_set, [NativeTypeName("ke_schedule *")] KernelEngine.Schedule.Native.ke_schedule* render_queue, [NativeTypeName("ke_schedule_set_id")] uint render_queue_set, [NativeTypeName("ke_settings *")] KernelEngine.Settings.Native.ke_settings* settings, [NativeTypeName("ke_owner *")] KernelEngine.Part.Native.ke_owner* out_pass);

    [DllImport("ke_render_shadow", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_shadow_set_log_callback", ExactSpelling = true)]
    public static extern void render_shadow_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);

    [DllImport("ke_render_shadow", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_shadow_parts", ExactSpelling = true)]
    [return: NativeTypeName("const ke_part *")]
    public static extern KernelEngine.Part.Native.ke_part* render_shadow_parts([NativeTypeName("size_t *")] nuint* out_count);
}
