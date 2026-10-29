using KernelEngine.Io.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Text.StbTrueType.Native;

public unsafe partial struct ke_font_loader_stb_params
{
    [NativeTypeName("ke_io *")]
    public KernelEngine.Io.Native.ke_io* io;
}
