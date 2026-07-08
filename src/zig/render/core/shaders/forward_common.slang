// Shared mesh vertex stage + fixed engine material set (set 1) + the
// surface-build prologue. Imported by both forward_lit.slang (inline shading)
// and gbuffer.slang (deferred encode): the vertex transform, the per-material
// binding, and populating a SurfaceState via the author's material.fragment()
// are byte-identical whether the fragment then shades inline or encodes to a
// G-buffer — only what happens *after* the SurfaceState is built differs.

import ke;   // VertexInfo, SurfaceState, IMaterial

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

// Set 1 — per material: the fixed engine material set. TestFlat and the other
// built-in materials source their surface fields from this UBO + textures.
struct Material {
    float4 base_color;
    float  metallic;
    float  roughness;
    float2 _pad;
};
[[vk::binding(0, 1)]] ConstantBuffer<Material> mat;
[[vk::binding(1, 1)]] Texture2D    albedo;
[[vk::binding(2, 1)]] SamplerState tex_sampler;
[[vk::binding(3, 1)]] Texture2D    normal_map;

// Set 2 — per object: transform.
struct PerObject {
    float4x4 mvp;
    float4x4 model;
};
[[vk::binding(0, 2)]] ConstantBuffer<PerObject> obj;

// Vertex stage: object → clip + world-space normal/tangent/pos for the fragment.
VsOut ke_forward_vs<T : IMaterial>(T material, VsIn input) {
    VertexInfo v;
    v.position = input.position;
    v.normal   = input.normal;
    v.uv       = input.uv;
    v.tangent  = float4(input.tangent, 1.0);
    v.color    = float3(1.0, 1.0, 1.0);
    material.vertex(v);   // author perturbation (object space)

    VsOut o;
    o.clip          = mul(obj.mvp, float4(v.position, 1.0));
    o.world_normal  = mul((float3x3)obj.model, v.normal);
    o.world_tangent = mul((float3x3)obj.model, v.tangent.xyz);
    o.world_pos     = mul(obj.model, float4(v.position, 1.0)).xyz;
    o.uv            = v.uv;
    return o;
}

// Builds the tangent→world basis, seeds a default SurfaceState, and lets the
// material populate it. The common prologue of both inline forward shading and
// deferred G-buffer encode.
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
    s.normal    = ng;   // default geometric normal
    s.emissive  = float3(0.0, 0.0, 0.0);
    s.ao        = 1.0;
    s.alpha     = 1.0;
    material.fragment(s);
    return s;
}
