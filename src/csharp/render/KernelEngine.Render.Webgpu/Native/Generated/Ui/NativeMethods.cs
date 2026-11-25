using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Render;
using global::KernelEngine.RenderGraph;
using global::KernelEngine.Text;

using KernelEngine.Ecs.Native;
using KernelEngine.Extraction.Native;
using KernelEngine.Framework.Nodes.Native;
using KernelEngine.Part.Native;
using KernelEngine.Render.Frame.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Schedule.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_ui", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_ui_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result render_ui_create([NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* main, [NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* render, [NativeTypeName("ke_extraction *")] KernelEngine.Extraction.Native.ke_extraction* extraction, [NativeTypeName("ke_render_service *")] KernelEngine.Render.Native.ke_render_service* service, [NativeTypeName("ke_gpu_device *")] KernelEngine.Render.Native.ke_gpu_device* device, [NativeTypeName("ke_render_frame *")] KernelEngine.Render.Frame.Native.ke_render_frame* frame, ke_render_ui_handle* out_ui);

    [DllImport("ke_render_ui", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_ui_systems_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result render_ui_systems_create(ke_render_ui* ui, [NativeTypeName("ke_schedule *")] KernelEngine.Schedule.Native.ke_schedule* render_prepare, [NativeTypeName("ke_schedule_set_id")] uint render_prepare_set, [NativeTypeName("ke_schedule *")] KernelEngine.Schedule.Native.ke_schedule* render_queue, [NativeTypeName("ke_schedule_set_id")] uint render_queue_set, [NativeTypeName("ke_owner *")] KernelEngine.Part.Native.ke_owner* out_systems);

    [DllImport("ke_render_ui", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_ui_set_log_callback", ExactSpelling = true)]
    public static extern void render_ui_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);

    [DllImport("ke_render_ui", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_ui_parts", ExactSpelling = true)]
    [return: NativeTypeName("const ke_part *")]
    public static extern KernelEngine.Part.Native.ke_part* render_ui_parts([NativeTypeName("size_t *")] nuint* out_count);

    [DllImport("ke_render_ui", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_ui_nodes_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result ui_nodes_create([NativeTypeName("ke_node_types *")] KernelEngine.Framework.Nodes.Native.ke_node_types* types, [NativeTypeName("ke_owner *")] KernelEngine.Part.Native.ke_owner* out_owner);
}
