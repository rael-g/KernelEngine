using KernelEngine.Kernel.Native;

namespace KernelEngine.Asset.Assimp.Native;

/// <summary>Construction parameters for <c>ke_asset_loader_assimp_create</c>.</summary>
public unsafe partial struct ke_asset_loader_assimp_params
{
    [NativeTypeName("struct ke_allocator *")]
    public ke_allocator* allocator;

    [NativeTypeName("struct ke_logger *")]
    public ke_logger* logger;
}
