using KernelEngine.Common.Native;

namespace KernelEngine.Text.Native;

public unsafe partial struct ke_font_loader_handle
{
    public ke_font_loader* @ref;

    [NativeTypeName("void (*)(ke_font_loader *)")]
    public delegate* unmanaged[Cdecl]<ke_font_loader*, void> destroy;
}
