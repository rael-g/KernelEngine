using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Common;
using global::KernelEngine.Ecs;
using global::KernelEngine.Physics;
using global::KernelEngine.Render;

using KernelEngine.Asset.Native;
using KernelEngine.Audio.Native;
using KernelEngine.Ecs.Native;
using KernelEngine.Framework.Native;
using KernelEngine.Io.Native;
using KernelEngine.Part.Native;
using KernelEngine.Result.Native;
using KernelEngine.Schedule.Native;
using KernelEngine.Scheduler.Native;
using KernelEngine.Settings.Native;

namespace KernelEngine.Framework.Nodes.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_node_types_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result node_types_create([NativeTypeName("ke_scheduler *")] KernelEngine.Scheduler.Native.ke_scheduler* scheduler, [NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* ecs, [NativeTypeName("ke_scene_tree *")] KernelEngine.Framework.Native.ke_scene_tree* scene_tree, [NativeTypeName("ke_input_actions *")] KernelEngine.Framework.Native.ke_input_actions* input_actions, ke_node_types_handle* out_types);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_node_types_systems_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result node_types_systems_create(ke_node_types* types, [NativeTypeName("ke_schedule *")] KernelEngine.Schedule.Native.ke_schedule* pre_update, [NativeTypeName("ke_schedule_set_id")] uint pre_update_set, [NativeTypeName("ke_schedule *")] KernelEngine.Schedule.Native.ke_schedule* fixed_update, [NativeTypeName("ke_schedule_set_id")] uint fixed_update_set, [NativeTypeName("ke_schedule *")] KernelEngine.Schedule.Native.ke_schedule* update, [NativeTypeName("ke_schedule_set_id")] uint update_set, [NativeTypeName("ke_schedule *")] KernelEngine.Schedule.Native.ke_schedule* post_update, [NativeTypeName("ke_schedule_set_id")] uint post_update_set, [NativeTypeName("ke_owner *")] KernelEngine.Part.Native.ke_owner* out_module);

    [DllImport("ke_framework", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_scene_files_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result scene_files_create([NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* ecs, ke_node_types* node_types, [NativeTypeName("ke_asset_resolver *")] KernelEngine.Asset.Native.ke_asset_resolver* assets, [NativeTypeName("ke_io *")] KernelEngine.Io.Native.ke_io* io, [NativeTypeName("ke_schedule *")] KernelEngine.Schedule.Native.ke_schedule* first_scene, [NativeTypeName("ke_schedule_set_id")] uint first_scene_set, [NativeTypeName("ke_settings *")] KernelEngine.Settings.Native.ke_settings* settings, ke_scene_files_handle* out_files);
}
