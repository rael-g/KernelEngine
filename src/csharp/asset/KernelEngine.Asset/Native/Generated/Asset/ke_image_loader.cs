using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Scheduler.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Asset.Native;

public unsafe partial struct ke_image_loader
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_image_loader *, const char *, ke_texture_data **)")]
    public delegate* unmanaged[Cdecl]<ke_image_loader*, sbyte*, ke_texture_data**, KernelEngine.Result.Native.ke_result> load_image;

    [NativeTypeName("void (*)(struct ke_image_loader *, ke_texture_data *)")]
    public delegate* unmanaged[Cdecl]<ke_image_loader*, ke_texture_data*, void> free_image;
}
