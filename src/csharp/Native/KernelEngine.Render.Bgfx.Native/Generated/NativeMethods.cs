using KernelEngine.Kernel.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Render.Bgfx.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_bgfx", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_bgfx_create", ExactSpelling = true)]
    public static extern ke_result render_bgfx_create([NativeTypeName("const ke_render_bgfx_params *")] ke_render_bgfx_params* @params, ke_render** out_render);

    [DllImport("ke_render_bgfx", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_bgfx_create_mesh_system_desc", ExactSpelling = true)]
    public static extern ke_result render_bgfx_create_mesh_system_desc([NativeTypeName("uint32_t")] uint mesh_cid, [NativeTypeName("uint32_t")] uint transform_cid, ke_system_desc* out_desc);

    [DllImport("ke_render_bgfx", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_bgfx_create_light_system_desc", ExactSpelling = true)]
    public static extern ke_result render_bgfx_create_light_system_desc([NativeTypeName("uint32_t")] uint light_cid, [NativeTypeName("uint32_t")] uint point_cid, [NativeTypeName("uint32_t")] uint spot_cid, [NativeTypeName("uint32_t")] uint transform_cid, ke_system_desc* out_desc);

    [DllImport("ke_render_bgfx", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_bgfx_create_camera_system_desc", ExactSpelling = true)]
    public static extern ke_result render_bgfx_create_camera_system_desc([NativeTypeName("uint32_t")] uint camera_cid, [NativeTypeName("uint32_t")] uint transform_cid, ke_system_desc* out_desc);

    [DllImport("ke_render_bgfx", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_bgfx_create_shadow_system_desc", ExactSpelling = true)]
    public static extern ke_result render_bgfx_create_shadow_system_desc([NativeTypeName("uint32_t")] uint light_cid, [NativeTypeName("uint32_t")] uint mesh_cid, [NativeTypeName("uint32_t")] uint transform_cid, ke_system_desc* out_desc);

    [DllImport("ke_render_bgfx", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_bgfx_create_skybox_system_desc", ExactSpelling = true)]
    public static extern ke_result render_bgfx_create_skybox_system_desc([NativeTypeName("uint32_t")] uint skybox_cid, ke_system_desc* out_desc);
}
