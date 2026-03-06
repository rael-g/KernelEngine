$input a_position, a_normal
$output v_normal, v_viewPos

#include <bgfx_shader.sh>

void main()
{
    vec4 viewPos = mul(u_modelView, vec4(a_position, 1.0));
    v_viewPos    = viewPos.xyz;
    gl_Position  = mul(u_proj, viewPos);
    v_normal     = normalize(mul(u_modelView, vec4(a_normal, 0.0)).xyz);
}
