using KernelEngine.Kernel.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Asset.StbImage.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_asset_stb_image", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_image_loader_stb_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Kernel.Native.ke_result image_loader_stb_create([NativeTypeName("const ke_image_loader_stb_params *")] ke_image_loader_stb_params* @params, ke_image_loader_handle* @out, ke_error** out_error);
}
