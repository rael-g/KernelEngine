using System.Runtime.InteropServices;

using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_binder_grouped", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_resource_binder_grouped_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_render_resource_binder_handle")]
    public static extern KernelEngine.Render.Native.ke_render_resource_binder_handle render_resource_binder_grouped_create([NativeTypeName("const ke_render_resource_binder_grouped_params *")] ke_render_resource_binder_grouped_params* @params, [NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);
}
