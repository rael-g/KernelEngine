using KernelEngine.Kernel.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Render.Core.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_core", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_core_register_default_systems", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Kernel.Native.ke_result render_core_register_default_systems([NativeTypeName("struct ke_world *")] KernelEngine.Kernel.Native.ke_world* world, [NativeTypeName("struct ke_render *")] KernelEngine.Kernel.Native.ke_render* render, [NativeTypeName("const ke_render_core_systems_params *")] ke_render_core_systems_params* @params);

    [DllImport("ke_render_core", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_core_shadow_system_set_map", ExactSpelling = true)]
    public static extern void render_core_shadow_system_set_map([NativeTypeName("struct ke_system_params *")] KernelEngine.Kernel.Native.ke_system_params* @params, [NativeTypeName("ke_shadow_map_handle")] KernelEngine.Kernel.Native.ke_shadow_map_handle handle);

    [DllImport("ke_render_core", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_core_mesh_system_describe", ExactSpelling = true)]
    public static extern void render_core_mesh_system_describe([NativeTypeName("uint32_t")] uint mesh_cid, [NativeTypeName("uint32_t")] uint transform_cid, [NativeTypeName("struct ke_system_params *")] KernelEngine.Kernel.Native.ke_system_params* out_params);

    [DllImport("ke_render_core", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_core_light_system_describe", ExactSpelling = true)]
    public static extern void render_core_light_system_describe([NativeTypeName("uint32_t")] uint light_cid, [NativeTypeName("uint32_t")] uint point_cid, [NativeTypeName("uint32_t")] uint spot_cid, [NativeTypeName("uint32_t")] uint transform_cid, [NativeTypeName("struct ke_system_params *")] KernelEngine.Kernel.Native.ke_system_params* out_params);

    [DllImport("ke_render_core", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_core_camera_system_describe", ExactSpelling = true)]
    public static extern void render_core_camera_system_describe([NativeTypeName("uint32_t")] uint camera_cid, [NativeTypeName("uint32_t")] uint transform_cid, [NativeTypeName("struct ke_system_params *")] KernelEngine.Kernel.Native.ke_system_params* out_params);

    [DllImport("ke_render_core", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_core_shadow_system_describe", ExactSpelling = true)]
    public static extern void render_core_shadow_system_describe([NativeTypeName("uint32_t")] uint light_cid, [NativeTypeName("uint32_t")] uint mesh_cid, [NativeTypeName("uint32_t")] uint transform_cid, [NativeTypeName("struct ke_system_params *")] KernelEngine.Kernel.Native.ke_system_params* out_params);

    [DllImport("ke_render_core", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_core_skybox_system_describe", ExactSpelling = true)]
    public static extern void render_core_skybox_system_describe([NativeTypeName("uint32_t")] uint skybox_cid, [NativeTypeName("struct ke_system_params *")] KernelEngine.Kernel.Native.ke_system_params* out_params);
}
