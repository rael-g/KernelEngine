using KernelEngine.Ecs.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Runtime.Native;
using KernelEngine.Text.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_ui
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_render_ui *, const char *, ke_texture_handle, const ke_glyph_metrics *, uint32_t, float, float, ke_ui_font_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_render_ui*, sbyte*, KernelEngine.Render.Native.ke_texture_handle, KernelEngine.Text.Native.ke_glyph_metrics*, uint, float, float, KernelEngine.Render.Native.ke_ui_font_handle*, KernelEngine.Result.Native.ke_result> load_font;
}
