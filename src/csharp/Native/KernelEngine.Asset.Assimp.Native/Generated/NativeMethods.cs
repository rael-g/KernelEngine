using System.Runtime.InteropServices;

namespace KernelEngine.Asset.Assimp.Native;

public static unsafe partial class NativeMethods
{
    [DllImport("ke_asset_loader_assimp", CallingConvention = CallingConvention.Cdecl,
               EntryPoint = "ke_asset_loader_assimp_create", ExactSpelling = true)]
    [return: NativeTypeName("ke_result")]
    public static extern KernelEngine.Kernel.Native.ke_result asset_loader_assimp_create(
        [NativeTypeName("const ke_asset_loader_assimp_params *")] ke_asset_loader_assimp_params* @params,
        ke_asset_loader** out_loader);
}
