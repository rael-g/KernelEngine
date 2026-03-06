$input v_texcoord0

#include <bgfx_shader.sh>

SAMPLER2D(s_blurTex, 0);

// x = step along X (1/width for horizontal pass, 0 for vertical)
// y = step along Y (0 for horizontal pass, 1/height for vertical)
uniform vec4 u_blurParams;

void main()
{
    vec2 offset = vec2(u_blurParams.x, u_blurParams.y);

    // 9-tap separable Gaussian (sigma ≈ 2).
    vec3 result = texture2D(s_blurTex, v_texcoord0).xyz * 0.227027;

    result += texture2D(s_blurTex, v_texcoord0 + 1.0 * offset).xyz * 0.194595;
    result += texture2D(s_blurTex, v_texcoord0 - 1.0 * offset).xyz * 0.194595;

    result += texture2D(s_blurTex, v_texcoord0 + 2.0 * offset).xyz * 0.121622;
    result += texture2D(s_blurTex, v_texcoord0 - 2.0 * offset).xyz * 0.121622;

    result += texture2D(s_blurTex, v_texcoord0 + 3.0 * offset).xyz * 0.054054;
    result += texture2D(s_blurTex, v_texcoord0 - 3.0 * offset).xyz * 0.054054;

    result += texture2D(s_blurTex, v_texcoord0 + 4.0 * offset).xyz * 0.016216;
    result += texture2D(s_blurTex, v_texcoord0 - 4.0 * offset).xyz * 0.016216;

    gl_FragColor = vec4(result, 1.0);
}
