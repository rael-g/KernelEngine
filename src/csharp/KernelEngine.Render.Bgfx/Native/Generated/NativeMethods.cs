using KernelEngine.Kernel.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Render.Bgfx.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_bgfx", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_bgfx_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Kernel.Native.ke_result render_bgfx_create([NativeTypeName("const ke_render_bgfx_params *")] ke_render_bgfx_params* @params, [NativeTypeName("ke_render **")] KernelEngine.Kernel.Native.ke_render** out_render);

    [DllImport("ke_render_bgfx", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_bgfx_get_last_fatal_error", ExactSpelling = true)]
    [return: NativeTypeName("const char *")]
    public static extern sbyte* render_bgfx_get_last_fatal_error();

    [DllImport("ke_render_bgfx", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_bgfx_create_mesh_system_params", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Kernel.Native.ke_result render_bgfx_create_mesh_system_params([NativeTypeName("uint32_t")] uint mesh_cid, [NativeTypeName("uint32_t")] uint transform_cid, [NativeTypeName("ke_system_params *")] KernelEngine.Kernel.Native.ke_system_params* out_params);

    [DllImport("ke_render_bgfx", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_bgfx_create_light_system_params", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Kernel.Native.ke_result render_bgfx_create_light_system_params([NativeTypeName("uint32_t")] uint light_cid, [NativeTypeName("uint32_t")] uint point_cid, [NativeTypeName("uint32_t")] uint spot_cid, [NativeTypeName("uint32_t")] uint transform_cid, [NativeTypeName("ke_system_params *")] KernelEngine.Kernel.Native.ke_system_params* out_params);

    [DllImport("ke_render_bgfx", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_bgfx_create_camera_system_params", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Kernel.Native.ke_result render_bgfx_create_camera_system_params([NativeTypeName("uint32_t")] uint camera_cid, [NativeTypeName("uint32_t")] uint transform_cid, [NativeTypeName("ke_system_params *")] KernelEngine.Kernel.Native.ke_system_params* out_params);

    [DllImport("ke_render_bgfx", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_bgfx_create_shadow_system_params", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Kernel.Native.ke_result render_bgfx_create_shadow_system_params([NativeTypeName("uint32_t")] uint light_cid, [NativeTypeName("uint32_t")] uint mesh_cid, [NativeTypeName("uint32_t")] uint transform_cid, [NativeTypeName("ke_system_params *")] KernelEngine.Kernel.Native.ke_system_params* out_params);

    [DllImport("ke_render_bgfx", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_bgfx_create_skybox_system_params", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Kernel.Native.ke_result render_bgfx_create_skybox_system_params([NativeTypeName("uint32_t")] uint skybox_cid, [NativeTypeName("ke_system_params *")] KernelEngine.Kernel.Native.ke_system_params* out_params);

    [DllImport("ke_render_bgfx", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_bgfx_shadow_system_set_map", ExactSpelling = true)]
    public static extern void render_bgfx_shadow_system_set_map([NativeTypeName("ke_system_params *")] KernelEngine.Kernel.Native.ke_system_params* @params, [NativeTypeName("ke_shadow_map_handle")] KernelEngine.Kernel.Native.ke_shadow_map_handle handle);
}
