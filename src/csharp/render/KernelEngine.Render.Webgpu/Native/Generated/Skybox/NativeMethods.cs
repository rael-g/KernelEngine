using System.Runtime.InteropServices;

using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_skybox", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_skybox_create", ExactSpelling = true)]
    public static extern ke_render_skybox_handle render_skybox_create([NativeTypeName("const ke_render_skybox_params *")] ke_render_skybox_params* @params, [NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);

    [DllImport("ke_render_skybox", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_skybox_set_log_callback", ExactSpelling = true)]
    public static extern void render_skybox_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
