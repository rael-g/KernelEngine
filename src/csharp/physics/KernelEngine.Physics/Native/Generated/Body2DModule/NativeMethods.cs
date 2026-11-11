using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;

using KernelEngine.Ecs.Native;
using KernelEngine.Framework.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;

namespace KernelEngine.Physics.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_physics_body2d", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_physics_body2d_module_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result physics_body2d_module_create([NativeTypeName("ke_runtime *")] KernelEngine.Runtime.Native.ke_runtime* runtime, [NativeTypeName("ke_ecs *")] KernelEngine.Ecs.Native.ke_ecs* ecs, ke_physics_2d* physics, [NativeTypeName("ke_scene_tree *")] KernelEngine.Framework.Native.ke_scene_tree* scene_tree, ke_physics_body2d_module_handle* out_module);

    [DllImport("ke_physics_body2d", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_physics_body2d_set_log_callback", ExactSpelling = true)]
    public static extern void physics_body2d_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
