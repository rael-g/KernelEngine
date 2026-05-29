namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_font_loader
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_font_loader *)")]
    public delegate* unmanaged[Cdecl]<ke_font_loader*, void> destroy;

    [NativeTypeName("ke_result (*)(struct ke_font_loader *, const char *, float, uint32_t, uint32_t, uint32_t, ke_font_data **)")]
    public delegate* unmanaged[Cdecl]<ke_font_loader*, sbyte*, float, uint, uint, uint, ke_font_data**, ke_result> load_font;

    [NativeTypeName("void (*)(struct ke_font_loader *, ke_font_data *)")]
    public delegate* unmanaged[Cdecl]<ke_font_loader*, ke_font_data*, void> free_font;
}
