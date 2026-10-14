struct VertexInfo {
    float3 position;
    float3 normal;
    float2 uv;
    float4 tangent;
    float3 color;
};

struct SurfaceState {
    float2   uv;
    float3   worldPos;
    float3x3 tbn;
    float3 albedo;
    float  metallic;
    float  roughness;
    float3 normal;
    float3 emissive;
    float  ao;
    float  alpha;
};

struct LightInput {
    float3 direction;
    float3 color;
    float  attenuation;
    float  shadow;
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
