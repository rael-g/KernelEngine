using KernelEngine.Asset.Native;
using KernelEngine.Io.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Asset.StbImage.Native;

public unsafe partial struct ke_image_loader_stb_params
{
    [NativeTypeName("ke_io *")]
    public KernelEngine.Io.Native.ke_io* io;
}
