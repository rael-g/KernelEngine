using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Asset.Assimp.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_asset_assimp", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_asset_loader_assimp_create", ExactSpelling = true)]
    public static extern ke_result asset_loader_assimp_create([NativeTypeName("const ke_asset_loader_assimp_params *")] ke_asset_loader_assimp_params* @params, [NativeTypeName("ke_asset_loader_handle *")] KernelEngine.Asset.Native.ke_asset_loader_handle* @out, ke_error** out_error);
}
