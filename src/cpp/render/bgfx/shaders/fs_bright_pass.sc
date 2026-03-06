$input v_texcoord0

#include <bgfx_shader.sh>

SAMPLER2D(s_hdrTex, 0);

uniform vec4 u_bloomParams; // x = threshold, y = (unused)

void main()
{
    vec3 color = texture2D(s_hdrTex, v_texcoord0).xyz;
    // Luminance-weighted bright extraction.
    float brightness = dot(color, vec3(0.2126, 0.7152, 0.0722));
    float contribution = max(brightness - u_bloomParams.x, 0.0);
    gl_FragColor = vec4(color * contribution, 1.0);
}
