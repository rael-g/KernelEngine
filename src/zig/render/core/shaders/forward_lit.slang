// Forward PBR pass, generic over IMaterial. Same lighting/IBL/shadow body as
// forward.slang, but the surface (albedo/metallic/roughness/normal) comes from
// the author's material.fragment() instead of being read inline from a fixed
// texture set. A material wrapper (see mat_test_flat.slang) binds a concrete
// IMaterial conformance into ke_forward_vs/ke_forward_fs and declares the entry
// points. Bind-group layouts and the vertex layout are byte-identical to
// forward.slang so the same pipeline layout / material bind group serve both.

import ke;   // VertexInfo, SurfaceState, IMaterial
import shadow_feature;   // sample_shadow_visibility — neutral default when off (white shadow map)
import ibl_feature;      // ibl_contribution — neutral default when off (black env cube)
import cluster_feature;  // accumulate_clustered_lights — neutral default when off (empty light lists)

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

// Set 0 — per frame. light_vp/shadow_map live in shadow_feature.slang,
// env/env_sampler in ibl_feature.slang, and cluster_grid/cluster_viewport +
// the point/spot light lists in cluster_feature.slang — this file declares
// none of them directly, but always calls their plain hook functions; a
// neutral-default resource makes each hook a no-op when its feature is off.
// shadow_params.z (directional light active) stays — a light-existence flag,
// orthogonal to whether it is shadowed.
struct PerFrame {
    float4   camera_pos;
    float4   light_dir;
    float4   light_color;
    float4   ambient;
    float4x4 sky_view_proj;
    float4   shadow_params;
    float4x4 view;
};
[[vk::binding(0, 0)]] ConstantBuffer<PerFrame> frame;

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

static const float PI = 3.14159265359;

float3 fresnel_schlick(float cos_theta, float3 f0) {
    return f0 + (1.0 - f0) * pow(saturate(1.0 - cos_theta), 5.0);
}
float distribution_ggx(float3 n, float3 h, float rough) {
    float a = rough * rough;
    float a2 = a * a;
    float ndoth = max(dot(n, h), 0.0);
    float d = ndoth * ndoth * (a2 - 1.0) + 1.0;
    return a2 / max(PI * d * d, 1e-4);
}
float geometry_schlick_ggx(float ndotv, float rough) {
    float r = rough + 1.0;
    float k = (r * r) / 8.0;
    return ndotv / (ndotv * (1.0 - k) + k);
}
float geometry_smith(float3 n, float3 v, float3 l, float rough) {
    return geometry_schlick_ggx(max(dot(n, v), 0.0), rough) *
           geometry_schlick_ggx(max(dot(n, l), 0.0), rough);
}
float3 pbr_direct(float3 n, float3 v, float3 l, float3 albedo_c, float3 f0,
                  float metallic, float rough, float3 radiance) {
    float ndotl = max(dot(n, l), 0.0);
    if (ndotl <= 0.0) return float3(0.0, 0.0, 0.0);
    float3 h   = normalize(v + l);
    float  ndf = distribution_ggx(n, h, rough);
    float  g   = geometry_smith(n, v, l, rough);
    float3 f   = fresnel_schlick(max(dot(h, v), 0.0), f0);
    float3 spec = (ndf * g * f) / (4.0 * max(dot(n, v), 0.0) * ndotl + 1e-4);
    float3 kd   = (float3(1.0, 1.0, 1.0) - f) * (1.0 - metallic);
    float3 diff = kd * albedo_c / PI;
    return (diff + spec) * radiance * ndotl;
}

// ── Generic pass entry logic; a material wrapper instantiates with its T. ──

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

float4 ke_forward_fs<T : IMaterial>(T material, VsOut input) {
    // Build the tangent->world basis and hand the material a populated surface.
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

    float3 albedo_c = s.albedo;
    float  metallic = s.metallic;
    float  rough    = s.roughness;
    float3 n        = normalize(s.normal);

    float3 v  = normalize(frame.camera_pos.xyz - input.world_pos);
    float3 f0 = lerp(float3(0.04, 0.04, 0.04), albedo_c, metallic);

    float3 lit = float3(0.0, 0.0, 0.0);

    if (frame.shadow_params.z > 0.5) {
        float3 l        = -normalize(frame.light_dir.xyz);
        float3 radiance = frame.light_color.rgb * frame.light_color.w;
        float  shadow   = sample_shadow_visibility(input.world_pos);
        lit += pbr_direct(n, v, l, albedo_c, f0, metallic, rough, radiance) * shadow;
    }

    float  view_z = mul(frame.view, float4(input.world_pos, 1.0)).z;
    lit += accumulate_clustered_lights(n, v, albedo_c, f0, metallic, rough, input.world_pos, input.clip.xy, view_z);

    float3 ibl = ibl_contribution(n, v, albedo_c, metallic);

    float3 ambient = frame.ambient.rgb * albedo_c * (1.0 - metallic);
    float3 color   = ambient + lit + s.emissive;
    color += ibl;

    // Linear HDR out — the ACES tonemap pass (tonemap.slang) does the tone
    // curve + display gamma on the resolve to the swapchain. Do not
    // tonemap/gamma-correct here: doing both here and in the tonemap pass
    // double-compresses the image (washed-out, intensity-insensitive colors).
    return float4(color, s.alpha);
}
