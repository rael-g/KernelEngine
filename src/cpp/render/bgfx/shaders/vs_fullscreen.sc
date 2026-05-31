$input a_position
$output v_texcoord0

#include <bgfx_shader.sh>

void main()
{
    gl_Position = vec4(a_position.x, a_position.y, 0.0, 1.0);
    // Convert NDC [-1,1] to texture UV [0,1]. The Y flip (0.5 - y*0.5) follows the same
    // D3D/GL convention as u_lightVP: clip Y+ = up, UV Y=0 = top. bgfx returns y_flip=false
    // for all backends (it applies the per-backend correction in setViewTransform), so this
    // formula is correct for Vulkan, D3D, OpenGL and Metal without a backend #if guard.
    v_texcoord0 = vec2(a_position.x * 0.5 + 0.5, 0.5 - a_position.y * 0.5);
}
