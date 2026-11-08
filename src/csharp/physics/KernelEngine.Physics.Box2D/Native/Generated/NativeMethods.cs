using System.Numerics;
using System.Runtime.InteropServices;

using global::KernelEngine.Logger;

using KernelEngine.Physics.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Physics.Box2D.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_physics_2d_box2d", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_physics_2d_box2d_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result physics_2d_box2d_create([NativeTypeName("const ke_physics_2d_box2d_config *")] ke_physics_2d_box2d_config* config, [NativeTypeName("ke_physics_2d_handle *")] KernelEngine.Physics.Native.ke_physics_2d_handle* out_world);

    [DllImport("ke_physics_2d_box2d", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_physics_2d_box2d_set_log_callback", ExactSpelling = true)]
    public static extern void physics_2d_box2d_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, global::KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void> callback, void* ctx);
}
