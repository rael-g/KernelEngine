// ke.surface.slang — surface types and material template interfaces.
// Authors implement IMaterial (or IUnlitMaterial, etc.) to define a surface.

struct VertexInfo {
    float3 position;   // object-space position (author modifies to deform)
    float3 normal;     // object-space normal
    float2 uv;         // texcoord0
    float4 tangent;    // tangent.xyz + handedness.w
    float3 color;      // vertex color
};

struct SurfaceState {
    float3 albedo;
    float3 normal;     // world-space normal (post fragment())
    float  metallic;
    float  roughness;
    float  ao;
    float  alpha;
    float  emissive;
};

struct LightInput {
    float3 direction;
    float3 color;
    float  attenuation;
    float  shadow;
    // convenience — populated by the pass
    float3 N;
    float3 V;
    float3 H;
    float  NdotL;
    float  NdotV;
    float  NdotH;
};

struct LightContribution {
    float3 diffuse;
    float3 specular;
};

// ── Template interfaces ───────────────────────────────────────────────────

interface IMaterial {
    void vertex(inout VertexInfo v);
    void fragment(inout SurfaceState s);
}

interface IUnlitMaterial {
    void vertex(inout VertexInfo v);
    float4 fragment(inout VertexInfo v);
}

interface IPostEffect {
    float4 fragment(float2 uv);
}

interface ISkyboxMaterial {
    float3 fragment(float3 viewDir);
}
