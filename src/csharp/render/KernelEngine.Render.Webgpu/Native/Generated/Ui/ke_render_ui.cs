using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.Render;
using global::KernelEngine.Text;

using KernelEngine.Result.Native;

namespace KernelEngine.Render.Webgpu.Native;

public unsafe partial struct ke_render_ui
{
    public void* handle;

    [NativeTypeName("ke_result (*)(struct ke_render_ui *, const char *, ke_texture_handle, const ke_glyph_metrics *, uint32_t, float, float, ke_ui_font_handle *)")]
    public delegate* unmanaged[Cdecl]<ke_render_ui*, sbyte*, global::KernelEngine.Render.TextureHandle, global::KernelEngine.Text.GlyphMetrics*, uint, float, float, global::KernelEngine.Render.UiFontHandle*, KernelEngine.Result.Native.Result> load_font;
}
