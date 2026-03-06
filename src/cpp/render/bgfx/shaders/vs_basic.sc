$input a_position, a_color0, a_normal, a_texcoord0, a_tangent
$output v_color0, v_normal, v_texcoord0, v_worldPos, v_shadowCoord, v_tangent

#include <bgfx_shader.sh>

uniform mat4 u_lightVP;

void main()
{
    vec4 worldPos   = mul(u_model[0], vec4(a_position, 1.0));
    gl_Position     = mul(u_viewProj, worldPos);
    v_worldPos      = worldPos.xyz;
    v_color0        = a_color0;
    vec3 N          = normalize(mul(u_model[0], vec4(a_normal,      0.0)).xyz);
    vec3 T          = normalize(mul(u_model[0], vec4(a_tangent.xyz, 0.0)).xyz);
    T               = normalize(T - dot(T, N) * N); // Gram-Schmidt re-orthogonalization
    v_normal        = N;
    v_tangent       = vec4(T, a_tangent.w);
    v_texcoord0     = a_texcoord0;
    v_shadowCoord   = mul(u_lightVP, worldPos);
}
