using System.Runtime.InteropServices;

using KernelEngine.Common.Native;

namespace KernelEngine.Physics.Box2D.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_physics_2d_box2d", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_physics_2d_box2d_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_physics_2d_handle")]
    public static extern KernelEngine.Physics.Native.ke_physics_2d_handle physics_2d_box2d_create([NativeTypeName("const ke_physics_2d_box2d_params *")] ke_physics_2d_box2d_params* @params, [NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);

    [DllImport("ke_physics_2d_box2d", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_physics_2d_box2d_set_log_callback", ExactSpelling = true)]
    public static extern void physics_2d_box2d_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
