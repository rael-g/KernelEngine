namespace KernelEngine.Kernel.Native;

public unsafe partial struct ke_font
{
    public void* handle;

    [NativeTypeName("void (*)(struct ke_font *)")]
    public delegate* unmanaged[Cdecl]<ke_font*, void> destroy;

    [NativeTypeName("ke_bool (*)(struct ke_font *, uint32_t, ke_glyph_metrics *)")]
    public delegate* unmanaged[Cdecl]<ke_font*, uint, ke_glyph_metrics*, byte> glyph;

    [NativeTypeName("ke_texture_handle (*)(struct ke_font *)")]
    public delegate* unmanaged[Cdecl]<ke_font*, ke_texture_handle> atlas_texture;

    [NativeTypeName("float (*)(struct ke_font *)")]
    public delegate* unmanaged[Cdecl]<ke_font*, float> line_height;
}
