using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Render;
using global::KernelEngine.RenderGraph;
using global::KernelEngine.Text;

using KernelEngine.Ecs.Native;
using KernelEngine.Extraction.Native;
using KernelEngine.Module.Native;
using KernelEngine.Render.Frame.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_ui", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_ui_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result render_ui_create([NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* main, [NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* render, [NativeTypeName("ke_extraction *")] KernelEngine.Extraction.Native.ke_extraction* extraction, [NativeTypeName("ke_render_service *")] KernelEngine.Render.Native.ke_render_service* service, [NativeTypeName("ke_gpu_device *")] KernelEngine.Render.Native.ke_gpu_device* device, [NativeTypeName("ke_render_frame *")] KernelEngine.Render.Frame.Native.ke_render_frame* frame, ke_render_ui_handle* out_ui);

    [DllImport("ke_render_ui", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_ui_systems_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result render_ui_systems_create(ke_render_ui* ui, [NativeTypeName("ke_module_handle *")] KernelEngine.Module.Native.ke_module_handle* out_module);

    [DllImport("ke_render_ui", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_ui_set_log_callback", ExactSpelling = true)]
    public static extern void render_ui_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
