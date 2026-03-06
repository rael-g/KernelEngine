$input v_texcoord0

#include <bgfx_shader.sh>

SAMPLER2D(s_hdrTex,   0);
SAMPLER2D(s_bloomTex, 1);

// x = exposure, y = bloom intensity, z = 1/gamma
uniform vec4 u_tonemapParams;

vec3 AcesTonemap(vec3 x)
{
    // ACES filmic curve (Narkowicz 2015 approximation).
    float a = 2.51;
    float b = 0.03;
    float c = 2.43;
    float d = 0.59;
    float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

void main()
{
    vec3 hdr   = texture2D(s_hdrTex,   v_texcoord0).xyz;
    vec3 bloom = texture2D(s_bloomTex, v_texcoord0).xyz;

    vec3 color = (hdr + bloom * u_tonemapParams.y) * u_tonemapParams.x;
    color = AcesTonemap(color);
    color = pow(color, vec3_splat(u_tonemapParams.z)); // gamma correction
    gl_FragColor = vec4(color, 1.0);
}
