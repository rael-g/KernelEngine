$input v_dir

#include <bgfx_shader.sh>

SAMPLERCUBE(s_skybox, 0);
uniform vec4 u_skyboxTint; // xyz = tint color, w = exposure multiplier

void main()
{
    vec3 color  = textureCube(s_skybox, v_dir).xyz;
    color      *= u_skyboxTint.xyz * u_skyboxTint.w;
    gl_FragColor = vec4(color, 1.0);
}
