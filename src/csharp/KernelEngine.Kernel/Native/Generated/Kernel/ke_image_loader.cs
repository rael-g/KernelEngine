namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_image_loader
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_image_loader *)")]
    public delegate* unmanaged[Cdecl]<ke_image_loader*, void> destroy;

    [NativeTypeName("ke_result (*)(struct ke_image_loader *, const char *, ke_texture_data **, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_image_loader*, sbyte*, ke_texture_data**, ke_error**, ke_result> load_image;

    [NativeTypeName("void (*)(struct ke_image_loader *, ke_texture_data *)")]
    public delegate* unmanaged[Cdecl]<ke_image_loader*, ke_texture_data*, void> free_image;
}
