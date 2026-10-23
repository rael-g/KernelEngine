using System.Runtime.InteropServices;

using KernelEngine.Common.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.View.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_view_space", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_view_space_rh_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.ke_result view_space_rh_create(ke_view_space_handle* out_view_space);

    [DllImport("ke_view_space", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_view_space_lh_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.ke_result view_space_lh_create(ke_view_space_handle* out_view_space);

    [DllImport("ke_view_space", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_view_space_set_log_callback", ExactSpelling = true)]
    public static extern void view_space_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, KernelEngine.Logger.Native.ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
