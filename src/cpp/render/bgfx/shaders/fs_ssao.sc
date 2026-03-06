$input v_texcoord0

#include <bgfx_shader.sh>

SAMPLER2D(s_gbufNormal, 0);
SAMPLER2D(s_gbufDepth,  1);
SAMPLER2D(s_ssaoNoise,  2);

uniform vec4 u_ssaoKernel[16]; // xyz = hemisphere sample (tangent space), w = unused
uniform vec4 u_ssaoParams;     // x = radius, y = bias, z = strength, w = unused
uniform vec4 u_ssaoProjInfo;   // x = 1/proj[0][0], y = 1/proj[1][1]

// Reconstruct view-space position from screen UV and positive linear depth.
// depth = -view_z (positive distance from camera).
vec3 ReconstructViewPos(vec2 uv, float depth)
{
    vec2 ndc = uv * 2.0 - 1.0;
    return vec3(ndc.x * u_ssaoProjInfo.x * depth,
                ndc.y * u_ssaoProjInfo.y * depth,
                -depth);
}

void main()
{
    float depth = texture2D(s_gbufDepth, v_texcoord0).r;
    // Background (depth near zero) has no occlusion.
    if (depth < 0.001)
    {
        gl_FragColor = vec4(1.0, 1.0, 1.0, 1.0);
        return;
    }

    vec3 fragPos = ReconstructViewPos(v_texcoord0, depth);
    vec3 normal  = normalize(texture2D(s_gbufNormal, v_texcoord0).xyz * 2.0 - 1.0);

    // Tile the 4x4 noise texture over the screen for random kernel rotation.
    vec2 noiseUV = gl_FragCoord.xy / 4.0;
    vec3 randVec = normalize(texture2D(s_ssaoNoise, noiseUV).xyz * 2.0 - 1.0);

    // Build TBN that orients the hemisphere kernel around the surface normal.
    vec3 tangent   = normalize(randVec - normal * dot(randVec, normal));
    vec3 bitangent = cross(normal, tangent);

    float radius   = u_ssaoParams.x;
    float bias     = u_ssaoParams.y;
    float strength = u_ssaoParams.z;

    float occlusion = 0.0;
    for (int i = 0; i < 16; ++i)
    {
        // Rotate kernel sample into view space.
        vec3 s = u_ssaoKernel[i].xyz;
        vec3 samplePos = fragPos + (tangent * s.x + bitangent * s.y + normal * s.z) * radius;

        // Project sample to screen UV.
        vec4 offset = mul(u_proj, vec4(samplePos, 1.0));
        offset.xyz /= offset.w;
        vec2 sampleUV = clamp(offset.xy * 0.5 + 0.5, vec2_splat(0.001), vec2_splat(0.999));

        // Sample linear depth at that screen position.
        float sampleDepth = texture2D(s_gbufDepth, sampleUV).r;

        // Range check: suppress contribution from geometrically distant occluders.
        float rangeCheck = smoothstep(0.0, 1.0, radius / abs(depth - sampleDepth));

        // Occluded when the sample sits behind the actual surface at sampleUV.
        occlusion += ((-samplePos.z) > sampleDepth + bias ? 1.0 : 0.0) * rangeCheck;
    }

    float ao = 1.0 - (occlusion / 16.0) * strength;
    gl_FragColor = vec4(ao, ao, ao, 1.0);
}
