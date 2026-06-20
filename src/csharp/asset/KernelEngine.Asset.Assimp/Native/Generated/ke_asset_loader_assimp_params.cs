using KernelEngine.Common.Native;

namespace KernelEngine.Asset.Assimp.Native;

public unsafe partial struct ke_asset_loader_assimp_params
{
    [NativeTypeName("struct ke_logger *")]
    public KernelEngine.Logger.Native.ke_logger* logger;
}
