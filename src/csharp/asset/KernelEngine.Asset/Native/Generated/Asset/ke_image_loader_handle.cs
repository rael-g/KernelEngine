using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Scheduler.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Asset.Native;

public unsafe partial struct ke_image_loader_handle
{
    public ke_image_loader* @ref;

    [NativeTypeName("void (*)(ke_image_loader *)")]
    public delegate* unmanaged[Cdecl]<ke_image_loader*, void> destroy;
}
