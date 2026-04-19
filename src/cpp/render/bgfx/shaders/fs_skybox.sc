$input v_dir

#include <bgfx_shader.sh>

SAMPLERCUBE(s_skybox, 0);
uniform vec4 u_skyboxTint; // xyz = tint color, w = exposure multiplier

void main()
{
    vec3 color  = textureCube(s_skybox, v_dir).xyz;
    color      *= u_skyboxTint.xyz * u_skyboxTint.w;
    gl_FragColor = vec4(color, 1.0);
    // Force skybox depth to exactly the far plane so any scene geometry
    // (with depth < 1.0) passes DEPTH_TEST_LESS and draws on top.
    gl_FragDepth = 1.0;
}
