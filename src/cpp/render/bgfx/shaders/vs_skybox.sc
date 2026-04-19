$input a_position
$output v_dir

#include <bgfx_shader.sh>

void main()
{
    v_dir = a_position;
    // Model matrix translates cube to camera position; camera's view matrix
    // cancels the translation so only rotation is visible (skybox always surrounds camera).
    // Fragment shader writes gl_FragDepth = 1.0 so final depth is at the far plane.
    gl_Position = mul(u_modelViewProj, vec4(a_position, 1.0));
}
