using KernelEngine.Common.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_ui
{
    public void* handle;

    [NativeTypeName("ke_ui_font_handle (*)(struct ke_render_ui *, const char *, ke_texture_handle, const ke_glyph_metrics *, uint32_t, float, float, ke_error **)")]
    public delegate* unmanaged[Cdecl]<ke_render_ui*, sbyte*, ke_texture_handle, ke_glyph_metrics*, uint, float, float, ke_error**, ke_ui_font_handle> load_font;
}
