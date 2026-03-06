$input a_position
$output v_texcoord0

#include <bgfx_shader.sh>

void main()
{
    gl_Position = vec4(a_position.x, a_position.y, 0.0, 1.0);
    // Convert NDC [-1,1] to texture UV [0,1] (Y flipped to match bgfx framebuffer origin).
    v_texcoord0 = vec2(a_position.x * 0.5 + 0.5, 0.5 - a_position.y * 0.5);
}
