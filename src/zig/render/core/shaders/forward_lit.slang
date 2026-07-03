// Forward PBR pass, generic over IMaterial. Same lighting/IBL/shadow body as
// forward.slang, but the surface (albedo/metallic/roughness/normal) comes from
// the author's material.fragment() instead of being read inline from a fixed
// texture set. A material wrapper (see mat_test_flat.slang) binds a concrete
// IMaterial conformance into ke_forward_vs/ke_forward_fs and declares the entry
// points. Bind-group layouts and the vertex layout are byte-identical to
// forward.slang so the same pipeline layout / material bind group serve both.

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

struct PointLight {
    float4 pos_radius;
    float4 color_intensity;
};

struct SpotLight {
    float4 pos_range;
    float4 dir_cos_inner;
    float4 color_intensity;
    float4 cone;
};

// Set 0 — per frame.
struct PerFrame {
    float4   camera_pos;
    float4   light_dir;
    float4   light_color;
    float4   ambient;
    float4x4 sky_view_proj;
    float4x4 light_vp;
    float4   shadow_params;
    float4x4 view;
    float4   cluster_grid;
    float4   cluster_viewport;
};
[[vk::binding(0, 0)]] ConstantBuffer<PerFrame> frame;
[[vk::binding(1, 0)]] TextureCube  env;
[[vk::binding(2, 0)]] SamplerState env_sampler;
[[vk::binding(3, 0)]] Texture2D    shadow_map;

// Set 3 — clustered light lists.
[[vk::binding(0, 3)]] StructuredBuffer<PointLight> point_lights;
[[vk::binding(1, 3)]] StructuredBuffer<SpotLight>  spot_lights;
[[vk::binding(2, 3)]] StructuredBuffer<uint>       point_indices;
[[vk::binding(3, 3)]] StructuredBuffer<uint>       point_counts;
[[vk::binding(4, 3)]] StructuredBuffer<uint>       spot_indices;
[[vk::binding(5, 3)]] StructuredBuffer<uint>       spot_counts;

uint cluster_index(float2 frag_xy, float view_z) {
    uint numX = (uint)frame.cluster_grid.x;
    uint numY = (uint)frame.cluster_grid.y;
    uint numZ = (uint)frame.cluster_grid.z;
    float near = frame.cluster_viewport.z;
    float far  = frame.cluster_viewport.w;
    uint ix = (uint)clamp(frag_xy.x / frame.cluster_viewport.x * (float)numX, 0.0, (float)(numX - 1u));
    uint iy = (uint)clamp(frag_xy.y / frame.cluster_viewport.y * (float)numY, 0.0, (float)(numY - 1u));
    float zs = (float)numZ * log(max(view_z, near) / near) / log(far / near);
    uint iz = (uint)clamp(zs, 0.0, (float)(numZ - 1u));
    return iz * numX * numY + iy * numX + ix;
}

float compute_shadow(float3 world_pos) {
    float4 sc = mul(frame.light_vp, float4(world_pos, 1.0));
    float3 coord = sc.xyz / sc.w;
    coord.x = coord.x * 0.5 + 0.5;
    coord.y = -coord.y * 0.5 + 0.5;
    if (any(coord < 0.0) || any(coord > 1.0)) return 1.0;
    float closest = shadow_map.Sample(env_sampler, coord.xy).r;
    return (coord.z - 0.005 > closest) ? 0.3 : 1.0;
}

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
        float  shadow   = (frame.shadow_params.x > 0.5) ? compute_shadow(input.world_pos) : 1.0;
        lit += pbr_direct(n, v, l, albedo_c, f0, metallic, rough, radiance) * shadow;
    }

    float  view_z    = mul(frame.view, float4(input.world_pos, 1.0)).z;
    uint   ci        = cluster_index(input.clip.xy, view_z);
    uint   maxLights = (uint)frame.cluster_grid.w;

    uint pcount = point_counts[ci];
    for (uint i = 0u; i < pcount; i++) {
        uint   li     = point_indices[ci * maxLights + i];
        float3 to_l   = point_lights[li].pos_radius.xyz - input.world_pos;
        float  dist   = length(to_l);
        float  radius = point_lights[li].pos_radius.w;
        float3 l      = to_l / max(dist, 1e-4);
        float  att    = clamp(1.0 - dist / max(radius, 1e-4), 0.0, 1.0);
        att *= att;
        float3 radiance = point_lights[li].color_intensity.rgb *
                          point_lights[li].color_intensity.w * att;
        lit += pbr_direct(n, v, l, albedo_c, f0, metallic, rough, radiance);
    }

    uint scount = spot_counts[ci];
    for (uint sp = 0u; sp < scount; sp++) {
        uint   li    = spot_indices[ci * maxLights + sp];
        float3 to_l  = spot_lights[li].pos_range.xyz - input.world_pos;
        float  dist  = length(to_l);
        float  range = spot_lights[li].pos_range.w;
        float3 l     = to_l / max(dist, 1e-4);
        float  datt  = clamp(1.0 - dist / max(range, 1e-4), 0.0, 1.0);
        datt *= datt;
        float3 sdir     = normalize(spot_lights[li].dir_cos_inner.xyz);
        float  cos_in   = spot_lights[li].dir_cos_inner.w;
        float  cos_out  = spot_lights[li].cone.x;
        float  cos_a    = dot(-l, sdir);
        float  catt     = clamp((cos_a - cos_out) / max(cos_in - cos_out, 1e-3), 0.0, 1.0);
        float3 radiance = spot_lights[li].color_intensity.rgb *
                          spot_lights[li].color_intensity.w * datt * catt;
        lit += pbr_direct(n, v, l, albedo_c, f0, metallic, rough, radiance);
    }

    float3 f_ibl       = fresnel_schlick(max(dot(n, v), 0.0), f0);
    float3 ibl_spec    = env.Sample(env_sampler, reflect(-v, n)).rgb * f_ibl;
    float3 ibl_diffuse = env.Sample(env_sampler, n).rgb * albedo_c * (1.0 - metallic) * (1.0 - f_ibl);
    float3 ibl         = ibl_spec + ibl_diffuse;

    float3 ambient = frame.ambient.rgb * albedo_c * (1.0 - metallic);
    float3 color   = ambient + lit + s.emissive;
    color += ibl;

    color = color / (color + 1.0);
    color = pow(color, float3(1.0 / 2.2, 1.0 / 2.2, 1.0 / 2.2));
    return float4(color, s.alpha);
}
