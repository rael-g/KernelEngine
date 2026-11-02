using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Ecs;

using KernelEngine.Framework.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_scene", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_scene_components_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result render_scene_components_create([NativeTypeName("ke_scene_component_set *")] KernelEngine.Framework.Native.ke_scene_component_set* set);
}
