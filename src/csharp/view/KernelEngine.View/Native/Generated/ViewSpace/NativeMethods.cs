using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.View.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_view_space", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_view_space_rh_create", ExactSpelling = true)]
    public static extern ke_view_space_handle view_space_rh_create([NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);

    [DllImport("ke_view_space", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_view_space_lh_create", ExactSpelling = true)]
    public static extern ke_view_space_handle view_space_lh_create([NativeTypeName("ke_error **")] KernelEngine.Common.Native.ke_error** out_error);
}
