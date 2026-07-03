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

// Feature <-> pass seam (§8.12 of RenderArchitectureV2.md): a shading pass calls
// visibility() generically and never names the feature that implements it.
// FullyLit is the no-op default (no shadow module present -> zero shadow
// bindings compiled into the pipeline). A shadow module contributes its own
// conformance (e.g. ShadowMapVisibility) owning its own texture/sampler/matrix,
// linked in only when that module is composed into the scene.
interface ILightVisibility {
    float visibility(float3 worldPos);
}

struct FullyLit : ILightVisibility {
    float visibility(float3 worldPos) { return 1.0; }
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
