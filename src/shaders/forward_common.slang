import ke;

struct VsIn {
    float3 position : POSITION;
    float3 normal   : NORMAL;
    float2 uv       : TEXCOORD0;
    float3 tangent  : TANGENT;
};

struct VsOut {
    float4 clip : SV_Position;
    [[vk::location(0)]] float3 world_normal  : NORMAL;
    [[vk::location(1)]] float3 world_pos     : POSITION;
    [[vk::location(2)]] float2 uv            : TEXCOORD0;
    [[vk::location(3)]] float3 world_tangent : TANGENT;
};

struct Material {
    float4 base_color;
    float  metallic;
    float  roughness;
    float  alpha_cutoff;
    float  ior;
    float  distortion_strength;
};
[[vk::binding(0, 1)]] ConstantBuffer<Material> mat;
[[vk::binding(1, 1)]] Texture2D    albedo;
[[vk::binding(2, 1)]] SamplerState tex_sampler;
[[vk::binding(3, 1)]] Texture2D    normal_map;

struct PerObject {
    float4x4 mvp;
    float4x4 model;
};
[[vk::binding(0, 2)]] ConstantBuffer<PerObject> obj;

VsOut ke_forward_vs<T : IMaterial>(T material, VsIn input) {
    VertexInfo v;
    v.position = input.position;
    v.normal   = input.normal;
    v.uv       = input.uv;
    v.tangent  = float4(input.tangent, 1.0);
    v.color    = float3(1.0, 1.0, 1.0);
    material.vertex(v);

    VsOut o;
    o.clip          = mul(obj.mvp, float4(v.position, 1.0));
    o.world_normal  = mul((float3x3)obj.model, v.normal);
    o.world_tangent = mul((float3x3)obj.model, v.tangent.xyz);
    o.world_pos     = mul(obj.model, float4(v.position, 1.0)).xyz;
    o.uv            = v.uv;
    return o;
}

SurfaceState ke_surface_from_vertex<T : IMaterial>(T material, VsOut input) {
    float3 ng = normalize(input.world_normal);
    float3 t  = normalize(input.world_tangent - ng * dot(ng, input.world_tangent));
    float3 b  = cross(ng, t);
    float3x3 tbn = float3x3(t, b, ng);

    SurfaceState s;
    s.uv        = input.uv;
    s.worldPos  = input.world_pos;
    s.tbn       = tbn;
    s.albedo    = float3(1.0, 1.0, 1.0);
    s.metallic  = 0.0;
    s.roughness = 0.5;
    s.normal    = ng;
    s.emissive  = float3(0.0, 0.0, 0.0);
    s.ao        = 1.0;
    s.alpha     = 1.0;
    material.fragment(s);
    return s;
}
