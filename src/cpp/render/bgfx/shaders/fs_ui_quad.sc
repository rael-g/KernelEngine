$input v_texcoord0, v_color0

#include <bgfx_shader.sh>

SAMPLER2D(s_texColor, 0);

// UI fragment: sample the source texture and modulate by the vertex tint. The vertex color is
// premultiplied alpha by convention so the alpha-blend (SRC=ONE, DST=INV_SRC_ALPHA) composites
// correctly over whatever the tonemap pass left in the backbuffer.
//
// For solid-color quads (texture binding skipped at the C++ side), bgfx supplies a default white
// 1x1 texture so sampling returns 1 and the output is purely the tint.
void main()
{
    vec4 tex = texture2D(s_texColor, v_texcoord0);
    // Premultiply texture RGB by its own alpha so atlases that store coverage in alpha (e.g.
    // font glyph atlases — white RGB + glyph-shape alpha) don't bleed a colored halo around
    // each glyph. The output blend is BLEND_ONE / INV_SRC_ALPHA (premultiplied), which adds
    // src.rgb to the framebuffer unconditionally — so any rgb > 0 at alpha = 0 paints a tint.
    // For solid-color quads (default 1×1 white texture: rgba=(1,1,1,1)), this is a no-op.
    tex.rgb *= tex.a;
    gl_FragColor = tex * v_color0;
}
