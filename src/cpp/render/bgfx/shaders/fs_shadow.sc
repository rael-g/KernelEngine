#include <bgfx_shader.sh>

void main()
{
    // Write normalized depth to red channel of R32F shadow map.
    gl_FragColor = vec4(gl_FragCoord.z, 0.0, 0.0, 1.0);
}
