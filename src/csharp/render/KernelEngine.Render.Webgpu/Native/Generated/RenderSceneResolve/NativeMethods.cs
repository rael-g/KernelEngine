using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Ecs;

using KernelEngine.Ecs.Native;
using KernelEngine.Extraction.Native;
using KernelEngine.Part.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Schedule.Native;

namespace KernelEngine.Render.Webgpu.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_render_scene", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_scene_resolve_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result render_scene_resolve_create([NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* main, [NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* render, [NativeTypeName("ke_extraction *")] KernelEngine.Extraction.Native.ke_extraction* extraction, [NativeTypeName("ke_render_service *")] KernelEngine.Render.Native.ke_render_service* service, [NativeTypeName("ke_render_assets *")] KernelEngine.Render.Native.ke_render_assets* assets, [NativeTypeName("ke_render_scene_resolve_handle *")] KernelEngine.Render.Native.ke_render_scene_resolve_handle* out_resolve);

    [DllImport("ke_render_scene", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_render_scene_resolve_systems_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result render_scene_resolve_systems_create([NativeTypeName("ke_render_scene_resolve *")] KernelEngine.Render.Native.ke_render_scene_resolve* scene, [NativeTypeName("ke_schedule *")] KernelEngine.Schedule.Native.ke_schedule* update, [NativeTypeName("ke_schedule_set_id")] uint update_set, [NativeTypeName("ke_schedule *")] KernelEngine.Schedule.Native.ke_schedule* post_update, [NativeTypeName("ke_schedule_set_id")] uint post_update_set, [NativeTypeName("ke_owner *")] KernelEngine.Part.Native.ke_owner* out_systems);
}
