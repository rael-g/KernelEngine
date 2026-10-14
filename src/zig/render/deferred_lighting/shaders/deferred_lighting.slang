import ke;
import gbuffer_encoding;
import shadow_feature;
import ibl_feature;
import cluster_feature;

struct DeferredFrame {
    float4   camera_pos;
    float4   light_dir;
    float4   light_color;
    float4   ambient;
    float4   shadow_params;
    float4   viewport;
    float4x4 view;
    float4x4 inv_view_proj;
};
[[vk::binding(0, 0)]] ConstantBuffer<DeferredFrame> frame;

[[vk::binding(0, 1)]] Texture2D<float4> g_albedo;
[[vk::binding(1, 1)]] Texture2D<float4> g_normal;
[[vk::binding(2, 1)]] Texture2D<float4> g_emissive;
[[vk::binding(3, 1)]] Texture2D<float>  g_depth;

struct VsOut {
    float4 clip : SV_Position;
    [[vk::location(0)]] float2 uv : TEXCOORD0;
};

[shader("vertex")]
VsOut vs_main(uint vid : SV_VertexID) {
    float2 pos = float2((vid & 1u) ? 3.0 : -1.0,
                        (vid & 2u) ? -3.0 : 1.0);
    VsOut o;
    o.clip = float4(pos, 0.0, 1.0);
    o.uv   = pos * float2(0.5, -0.5) + 0.5;
    return o;
}

[shader("fragment")]
float4 fs_main(VsOut input) : SV_Target0 {
    int2 px = int2(input.clip.xy);

    float depth = g_depth.Load(int3(px, 0)).x;
    if (depth >= 1.0) discard;

    float2 ndc = float2(input.uv.x * 2.0 - 1.0, 1.0 - input.uv.y * 2.0);
    float4 h = mul(frame.inv_view_proj, float4(ndc, depth, 1.0));
    float3 world_pos = h.xyz / h.w;

    float4 a0 = g_albedo.Load(int3(px, 0));
    float4 a1 = g_normal.Load(int3(px, 0));
    float4 a2 = g_emissive.Load(int3(px, 0));
    float3 albedo_c  = a0.rgb;
    float  metallic  = a0.a;
    float3 n         = ke_oct_decode(a1.rg);
    float  rough     = a1.b;
    float  ao        = a1.a;
    float3 emissive  = a2.rgb;
    float  alpha     = a2.a;

    float3 v  = normalize(frame.camera_pos.xyz - world_pos);
    float3 f0 = lerp(float3(0.04, 0.04, 0.04), albedo_c, metallic);

    float3 lit = float3(0.0, 0.0, 0.0);

    if (frame.shadow_params.z > 0.5) {
        float3 l        = -normalize(frame.light_dir.xyz);
        float3 radiance = frame.light_color.rgb * frame.light_color.w;
        float  shadow   = sample_shadow_visibility(world_pos);
        lit += pbr_direct(n, v, l, albedo_c, f0, metallic, rough, radiance) * shadow;
    }

    float view_z = mul(frame.view, float4(world_pos, 1.0)).z;
    lit += accumulate_clustered_lights(n, v, albedo_c, f0, metallic, rough, world_pos, input.clip.xy, view_z);

    float3 ibl     = ibl_contribution(n, v, albedo_c, metallic);
    float3 ambient = frame.ambient.rgb * albedo_c * (1.0 - metallic) * ao;
    float3 color   = ambient + lit + emissive + ibl;

    return float4(color, alpha);
}
