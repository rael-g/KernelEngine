using KernelEngine.Kernel.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.DevPlatform.Win32.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_dev_platform_win32", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_dev_platform_create_win32", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Kernel.Native.ke_result dev_platform_create_win32([NativeTypeName("ke_allocator *")] KernelEngine.Kernel.Native.ke_allocator* alloc, ke_dev_platform** out_platform);
}
