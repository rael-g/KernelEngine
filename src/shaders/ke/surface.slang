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
    // ── Read-only context (engine-populated before fragment()) ──
    float2   uv;        // texcoord0
    float3   worldPos;  // world-space fragment position
    float3x3 tbn;       // tangent -> world basis, for normal-map decode
    // ── Author-writable surface (PBR metallic-roughness) ──
    float3 albedo;      // default (1,1,1)
    float  metallic;    // default 0
    float  roughness;   // default 0.5
    float3 normal;      // world-space; default = geometric normal
    float3 emissive;    // default 0
    float  ao;          // default 1
    float  alpha;       // default 1
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

// Shadow visibility, indirect/IBL contribution, and dynamic-light
// accumulation are NOT generic hooks here — they are plain functions in
// shadow_feature.slang / ibl_feature.slang / cluster_feature.slang, called
// directly by forward_lit.slang. Each reads a neutral-default resource
// (white shadow map, black env cube, empty light list) when its producing
// feature is absent, so the hook is a no-op without needing a type to select.

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
