using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;

using KernelEngine.Job.Native;
using KernelEngine.Part.Native;
using KernelEngine.Physics.Native;
using KernelEngine.Result.Native;
using KernelEngine.Settings.Native;

namespace KernelEngine.Physics.Box2D.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_physics_2d_box2d", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_physics_2d_box2d_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result physics_2d_box2d_create([NativeTypeName("ke_job_system *")] KernelEngine.Job.Native.ke_job_system* job_system, [NativeTypeName("ke_settings *")] KernelEngine.Settings.Native.ke_settings* settings, [NativeTypeName("ke_physics_2d_handle *")] KernelEngine.Physics.Native.ke_physics_2d_handle* out_world);

    [DllImport("ke_physics_2d_box2d", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_physics_2d_box2d_parts", ExactSpelling = true)]
    [return: NativeTypeName("const ke_part *")]
    public static extern KernelEngine.Part.Native.ke_part* physics_2d_box2d_parts([NativeTypeName("size_t *")] nuint* out_count);

    [DllImport("ke_physics_2d_box2d", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_physics_2d_box2d_set_log_callback", ExactSpelling = true)]
    public static extern void physics_2d_box2d_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
