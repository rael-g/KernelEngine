using KernelEngine.Asset.Native;
using KernelEngine.Common.Native;
using KernelEngine.Logger.Native;

namespace KernelEngine.Asset.Assimp.Native;

public unsafe partial struct ke_asset_loader_assimp_params
{
    [NativeTypeName("struct ke_logger *")]
    public KernelEngine.Logger.Native.ke_logger* logger;
}
