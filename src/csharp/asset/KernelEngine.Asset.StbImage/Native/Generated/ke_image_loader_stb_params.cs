using KernelEngine.Kernel.Native;

namespace KernelEngine.Asset.StbImage.Native;

public unsafe partial struct ke_image_loader_stb_params
{
    [NativeTypeName("struct ke_logger *")]
    public KernelEngine.Kernel.Native.ke_logger* logger;
}
