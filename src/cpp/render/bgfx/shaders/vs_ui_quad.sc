$input  a_position, a_texcoord0, a_color0
$output v_texcoord0, v_color0

#include <bgfx_shader.sh>

// UI quad vertex: positions arrive in backbuffer pixel coords (top-left origin).
// View 7 is set up with an orthographic projection that maps [0, vp_w] x [0, vp_h] (Y-down)
// to NDC, so we just pass through the position via u_viewProj.
void main()
{
    gl_Position = mul(u_viewProj, vec4(a_position, 1.0));
    v_texcoord0 = a_texcoord0;
    v_color0    = a_color0;
}
