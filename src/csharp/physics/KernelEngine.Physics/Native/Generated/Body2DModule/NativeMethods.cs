using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Physics;

using KernelEngine.Ecs.Native;
using KernelEngine.Framework.Native;
using KernelEngine.Framework.Nodes.Native;
using KernelEngine.Part.Native;
using KernelEngine.Result.Native;
using KernelEngine.Schedule.Native;

namespace KernelEngine.Physics.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_physics_body2d", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_physics_body2d_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result physics_body2d_create([NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* ecs, ke_physics_2d* physics, [NativeTypeName("ke_scene_tree *")] KernelEngine.Framework.Native.ke_scene_tree* scene_tree, [NativeTypeName("ke_schedule *")] KernelEngine.Schedule.Native.ke_schedule* fixed_post_update, [NativeTypeName("ke_schedule_set_id")] uint fixed_post_update_set, [NativeTypeName("ke_owner *")] KernelEngine.Part.Native.ke_owner* out_module);

    [DllImport("ke_physics_body2d", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_physics_body2d_parts", ExactSpelling = true)]
    [return: NativeTypeName("const ke_part *")]
    public static extern KernelEngine.Part.Native.ke_part* physics_body2d_parts([NativeTypeName("size_t *")] nuint* out_count);

    [DllImport("ke_physics_body2d", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_physics_body2d_set_log_callback", ExactSpelling = true)]
    public static extern void physics_body2d_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);

    [DllImport("ke_physics_body2d", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_physics_nodes_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result physics_nodes_create([NativeTypeName("ke_node_types *")] KernelEngine.Framework.Nodes.Native.ke_node_types* types, [NativeTypeName("ke_owner *")] KernelEngine.Part.Native.ke_owner* out_owner);
}
