using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_core", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_module_create", ExactSpelling = true)]
    public static extern ke_render_module_handle render_module_create([NativeTypeName("ke_runtime *")] KernelEngine.Runtime.Native.ke_runtime* runtime, [NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* ecs, ke_gpu_device* device, [NativeTypeName("ke_bool")] byte default_passes, [NativeTypeName("struct ke_logger *")] KernelEngine.Logger.Native.ke_logger* logger, [NativeTypeName("const ke_render_cluster_params *")] ke_render_cluster_params* cluster_params, [NativeTypeName("const ke_render_feature_params *")] ke_render_feature_params* feature_params, ke_error** out_error);

    [DllImport("ke_render_core", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_module_core", ExactSpelling = true)]
    public static extern ke_render_core* render_module_core(ke_render_module* module);
}
