using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Ecs;

using KernelEngine.Asset.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Extraction.Native;
using KernelEngine.Module.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_scene", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_scene_resolve_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result render_scene_resolve_create([NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* main, [NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* render, [NativeTypeName("ke_extraction *")] KernelEngine.Extraction.Native.ke_extraction* extraction, [NativeTypeName("ke_render_service *")] KernelEngine.Render.Native.ke_render_service* service, [NativeTypeName("ke_asset_resolver *")] KernelEngine.Asset.Native.ke_asset_resolver* resolver, [NativeTypeName("ke_render_scene_resolve_handle *")] KernelEngine.Render.Native.ke_render_scene_resolve_handle* out_resolve);

    [DllImport("ke_render_scene", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_scene_resolve_systems_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result render_scene_resolve_systems_create([NativeTypeName("ke_render_scene_resolve *")] KernelEngine.Render.Native.ke_render_scene_resolve* scene, [NativeTypeName("ke_module_handle *")] KernelEngine.Module.Native.ke_module_handle* out_module);
}
