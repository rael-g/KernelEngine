using KernelEngine.Common.Native;

namespace KernelEngine.Text.StbTrueType.Native;

public unsafe partial struct ke_font_loader_stb_params
{
    [NativeTypeName("struct ke_logger *")]
    public KernelEngine.Logger.Native.ke_logger* logger;
}
