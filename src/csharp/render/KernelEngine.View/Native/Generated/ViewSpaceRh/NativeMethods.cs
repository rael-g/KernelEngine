using System.Numerics;
using System.Runtime.InteropServices;

using KernelEngine.Result.Native;

namespace KernelEngine.View.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_view_space", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_view_space_rh_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.Result view_space_rh_create(ke_view_space_handle* out_view_space);
}
