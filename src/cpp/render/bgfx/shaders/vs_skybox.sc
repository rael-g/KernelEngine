$input a_position
$output v_dir

#include <bgfx_shader.sh>

void main()
{
    v_dir = a_position;
    // Use the rotation-only view×proj set on this view.
    // xyww depth trick: NDC depth = w/w = 1.0, so skybox sits at the far plane
    // and scene geometry (depth < 1.0) renders in front of it.
    vec4 pos    = mul(u_viewProj, vec4(a_position, 1.0));
    gl_Position = pos.xyww;
}
