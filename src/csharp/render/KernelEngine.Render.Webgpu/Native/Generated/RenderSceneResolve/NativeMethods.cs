using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Ecs;

using KernelEngine.Asset.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_scene", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_scene_resolve_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result render_scene_resolve_create([NativeTypeName("const ke_render_scene_resolve_params *")] ke_render_scene_resolve_params* @params, [NativeTypeName("ke_render_scene_resolve_handle *")] KernelEngine.Render.Native.ke_render_scene_resolve_handle* out_resolve);
}
