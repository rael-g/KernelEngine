using KernelEngine.Common.Native;
using System.Runtime.InteropServices;

namespace KernelEngine.Asset.Assimp.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_asset_assimp", CallingConvention = CallingConvention.Cdecl, EntryPoint = "ke_asset_loader_assimp_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_asset_loader_handle")]
    public static extern KernelEngine.Asset.Native.ke_asset_loader_handle asset_loader_assimp_create([NativeTypeName("const ke_asset_loader_assimp_params *")] ke_asset_loader_assimp_params* @params, ke_error** out_error);
}
