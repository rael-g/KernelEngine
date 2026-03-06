$input v_texcoord0

#include <bgfx_shader.sh>

SAMPLER2D(s_ssaoInput, 0);

uniform vec4 u_ssaoBlurParams; // x = 1/width, y = 1/height

void main()
{
    vec2 texel = u_ssaoBlurParams.xy;
    float result = 0.0;
    for (int x = -2; x <= 2; ++x)
    {
        for (int y = -2; y <= 2; ++y)
        {
            vec2 offset = vec2(float(x), float(y)) * texel;
            result += texture2D(s_ssaoInput, v_texcoord0 + offset).r;
        }
    }
    result /= 25.0;
    gl_FragColor = vec4(result, result, result, 1.0);
}
