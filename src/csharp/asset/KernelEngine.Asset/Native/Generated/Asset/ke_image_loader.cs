using KernelEngine.Common.Native;
using KernelEngine.Render.Native;
using KernelEngine.Scheduler.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Asset.Native;

public unsafe partial struct ke_image_loader
{
    public void* handle;

    [NativeTypeName("ke_texture_data *(*)(struct ke_image_loader *, const char *, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_image_loader*, sbyte*, KernelEngine.Common.Native.ke_error**, ke_texture_data*> load_image;

    [NativeTypeName("void (*)(struct ke_image_loader *, ke_texture_data *)")]
    public delegate* unmanaged[Cdecl]<ke_image_loader*, ke_texture_data*, void> free_image;
}
