// Forward lit mesh with a glTF-style material. Descriptor sets are split by
// update frequency (Vulkan/WebGPU convention): set 0 = per-object (transform +
// light, dynamic-offset uniform), set 1 = per-material (base color factor +
// albedo texture + sampler). No IMaterial template yet (that is §8); direct
// entry points. Matrices arrive row-major (row-vector convention) so Slang's
// mul(M, v) lowering to WGSL transforms correctly.

struct VsIn {
    float3 position : POSITION;
    float3 normal   : NORMAL;
    float2 uv       : TEXCOORD0;
};

struct VsOut {
    float4 clip : SV_Position;
    [[vk::location(0)]] float3 world_normal : NORMAL;
    [[vk::location(1)]] float2 uv           : TEXCOORD0;
};

// Set 0 — per object: model*view*proj + model (for the normal) + light.
struct PerObject {
    float4x4 mvp;
    float4x4 model;
    float4   light_dir; // xyz = direction the light travels (normalized)
};
[[vk::binding(0, 0)]] ConstantBuffer<PerObject> obj;

// Set 1 — per material: glTF base-color factor multiplied by the albedo texture.
struct Material {
    float4 base_color;
};
[[vk::binding(0, 1)]] ConstantBuffer<Material> mat;
[[vk::binding(1, 1)]] Texture2D    albedo;
[[vk::binding(2, 1)]] SamplerState albedo_sampler;

[shader("vertex")]
VsOut vs_main(VsIn input) {
    VsOut o;
    o.clip         = mul(obj.mvp, float4(input.position, 1.0));
    o.world_normal = mul((float3x3)obj.model, input.normal);
    o.uv           = input.uv;
    return o;
}

[shader("fragment")]
float4 fs_main(VsOut input) : SV_Target {
    float3 n     = normalize(input.world_normal);
    float  ndotl = max(dot(n, -normalize(obj.light_dir.xyz)), 0.0);
    float4 tex   = albedo.Sample(albedo_sampler, input.uv);
    float3 base  = mat.base_color.rgb * tex.rgb;
    float3 lit   = base * (0.15 + 0.85 * ndotl);
    return float4(lit, 1.0);
}
