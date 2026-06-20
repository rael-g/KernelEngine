using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Asset.StbImage.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_asset_stb_image", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_image_loader_stb_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_image_loader_handle")]
    public static extern KernelEngine.Asset.Native.ke_image_loader_handle image_loader_stb_create([NativeTypeName("const ke_image_loader_stb_params *")] ke_image_loader_stb_params* @params, ke_error** out_error);
}
