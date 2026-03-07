#include <bgfx_compute.sh>

// Cluster grid: 16x8x24
// Max 64 lights per cluster
// Max 4096 total lights

// Each ClusterAABB uses 2 vec4 (min, max)
BUFFER_RO(b_clusterBounds, vec4, 0);
// Each PointLight uses 2 vec4 (pos_r, color)
BUFFER_RO(b_pointLights, vec4, 1);
// Each SpotLight uses 3 vec4 (pos_r, dir_cosI, color_cosO)
BUFFER_RO(b_spotLights, vec4, 2);

// Outputs (uints fit in typed buffers)
BUFFER_RW(b_pointLightIndices, uint, 3);
BUFFER_RW(b_pointLightCount, uint, 4);
BUFFER_RW(b_spotLightIndices, uint, 5);
BUFFER_RW(b_spotLightCount, uint, 6);

uniform vec4 u_clusterParams;  // x=numX, y=numY, z=numZ, w=maxLightsPerCluster
uniform vec4 u_clusterParams2; // x=pointLightCount, y=spotLightCount
uniform mat4 u_computeView;

NUM_THREADS(1, 1, 1)
void main()
{
    uint clusterIndex = gl_GlobalInvocationID.z * uint(u_clusterParams.x * u_clusterParams.y) +
                        gl_GlobalInvocationID.y * uint(u_clusterParams.x) +
                        gl_GlobalInvocationID.x;

    vec3 aabbMin = b_clusterBounds[clusterIndex * 2u].xyz;
    vec3 aabbMax = b_clusterBounds[clusterIndex * 2u + 1u].xyz;

    uint maxLights = uint(u_clusterParams.w);
    uint pointCount = uint(u_clusterParams2.x);
    uint spotCount = uint(u_clusterParams2.y);

    // ── Point light culling ────────────────────────────────────────────────────
    uint pCount = 0;
    for (uint pi = 0; pi < pointCount && pCount < maxLights; ++pi)
    {
        vec4 pos_r = b_pointLights[pi * 2u];
        // Transform position to view space
        vec3 pPos = mul(u_computeView, vec4(pos_r.xyz, 1.0)).xyz;
        float pRad = pos_r.w;

        vec3 closest = max(aabbMin, min(pPos, aabbMax));
        vec3 distVec = closest - pPos;
        if (dot(distVec, distVec) <= (pRad * pRad))
        {
            b_pointLightIndices[clusterIndex * maxLights + pCount] = pi;
            pCount++;
        }
    }
    b_pointLightCount[clusterIndex] = pCount;

    // ── Spot light culling (conservative sphere check) ─────────────────────────
    uint sCount = 0;
    for (uint si = 0; si < spotCount && sCount < maxLights; ++si)
    {
        vec4 pos_r = b_spotLights[si * 3u];
        // Transform position to view space
        vec3 sPos = mul(u_computeView, vec4(pos_r.xyz, 1.0)).xyz;
        float sRng = pos_r.w;

        vec3 closest = max(aabbMin, min(sPos, aabbMax));
        vec3 distVec = closest - sPos;
        if (dot(distVec, distVec) <= (sRng * sRng))
        {
            b_spotLightIndices[clusterIndex * maxLights + sCount] = si;
            sCount++;
        }
    }
    b_spotLightCount[clusterIndex] = sCount;
}
