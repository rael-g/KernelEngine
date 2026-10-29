using System.Runtime.InteropServices;

using KernelEngine.Asset.Native;
using KernelEngine.Io.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Asset.StbImage.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_asset_stb_image", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_image_loader_stb_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Result.Native.ke_result image_loader_stb_create([NativeTypeName("const ke_image_loader_stb_params *")] ke_image_loader_stb_params* @params, [NativeTypeName("ke_image_loader_handle *")] KernelEngine.Asset.Native.ke_image_loader_handle* out_loader);

    [DllImport("ke_asset_stb_image", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_asset_stb_image_set_log_callback", ExactSpelling = true)]
    public static extern void asset_stb_image_set_log_callback([NativeTypeName("ke_log_callback")] delegate* unmanaged[Cdecl]<void*, KernelEngine.Logger.Native.ke_log_level, sbyte*, sbyte*, void> callback, void* ctx);
}
