// Forward PBR (Cook-Torrance GGX metallic-roughness) with tangent-space normal
// mapping and a single directional light. Descriptor sets split by update
// frequency (Vulkan/WebGPU convention): set 0 = per-frame (camera + light),
// set 1 = per-material (glTF base color + metallic/roughness + albedo + normal),
// set 2 = per-object (transform, dynamic offset). Matrices arrive row-major
// (row-vector convention) so Slang's mul(M, v) lowers to WGSL correctly. Inline
// Reinhard + gamma is transitional until the tonemap pass (example 10).

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

// Brute-force point light cap (matches the per-frame uniform array below).
static const uint MAX_POINT_LIGHTS = 16;

// A point light packed for the per-frame uniform.
struct PointLight {
    float4 pos_radius;       // xyz = world position, w = radius
    float4 color_intensity;  // rgb = color, w = intensity
};

// Set 0 — per frame: camera + light + environment cubemap (skybox / IBL) + shadow map.
struct PerFrame {
    float4   camera_pos;    // xyz
    float4   light_dir;     // xyz = direction the directional light travels (normalized)
    float4   light_color;   // rgb, w = intensity
    float4   ambient;       // rgb
    float4x4 sky_view_proj; // rotation-only view*proj — used by the skybox pass
    float4x4 light_vp;      // directional light view*proj — for the shadow lookup
    float4   shadow_params; // x = shadow active, y = point light count, z = directional active
    PointLight point_lights[MAX_POINT_LIGHTS];
};
[[vk::binding(0, 0)]] ConstantBuffer<PerFrame> frame;
[[vk::binding(1, 0)]] TextureCube  env;         // environment (black 1×1 when no skybox)
[[vk::binding(2, 0)]] SamplerState env_sampler;
[[vk::binding(3, 0)]] Texture2D    shadow_map;  // R32F light-space depth

// Translated from the legacy bgfx ComputeShadow: project into light clip space,
// to UV, compare the fragment's depth against the stored nearest occluder.
float compute_shadow(float3 world_pos) {
    float4 sc = mul(frame.light_vp, float4(world_pos, 1.0));
    float3 coord = sc.xyz / sc.w;
    coord.x = coord.x * 0.5 + 0.5;
    coord.y = -coord.y * 0.5 + 0.5;
    if (any(coord < 0.0) || any(coord > 1.0)) return 1.0;
    float closest = shadow_map.Sample(env_sampler, coord.xy).r;
    return (coord.z - 0.005 > closest) ? 0.3 : 1.0;
}

// Set 1 — per material: glTF metallic-roughness + albedo + tangent-space normal.
struct Material {
    float4 base_color;
    float  metallic;
    float  roughness;
    float2 _pad;
};
[[vk::binding(0, 1)]] ConstantBuffer<Material> mat;
[[vk::binding(1, 1)]] Texture2D    albedo;
[[vk::binding(2, 1)]] SamplerState tex_sampler;
[[vk::binding(3, 1)]] Texture2D    normal_map; // tangent-space, RGB = (n+1)/2

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

// Cook-Torrance contribution of one light (L = surface→light, radiance already
// attenuated). Translated from the legacy bgfx PbrDirect.
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

[shader("vertex")]
VsOut vs_main(VsIn input) {
    VsOut o;
    o.clip          = mul(obj.mvp, float4(input.position, 1.0));
    o.world_normal  = mul((float3x3)obj.model, input.normal);
    o.world_tangent = mul((float3x3)obj.model, input.tangent);
    o.world_pos     = mul(obj.model, float4(input.position, 1.0)).xyz;
    o.uv            = input.uv;
    return o;
}

[shader("fragment")]
float4 fs_main(VsOut input) : SV_Target {
    float3 albedo_c = mat.base_color.rgb * albedo.Sample(tex_sampler, input.uv).rgb;
    float  metallic = mat.metallic;
    float  rough    = mat.roughness;

    // Tangent-space normal -> world. Default flat-normal map (0,0,1) leaves n = geo normal.
    float3 ng = normalize(input.world_normal);
    float3 t  = normalize(input.world_tangent - ng * dot(ng, input.world_tangent)); // Gram-Schmidt
    float3 b  = cross(ng, t);
    float3 tn = normal_map.Sample(tex_sampler, input.uv).rgb * 2.0 - 1.0;
    float3 n  = normalize(t * tn.x + b * tn.y + ng * tn.z);

    float3 v  = normalize(frame.camera_pos.xyz - input.world_pos);
    float3 f0 = lerp(float3(0.04, 0.04, 0.04), albedo_c, metallic);

    float3 lit = float3(0.0, 0.0, 0.0);

    // Directional light — only when a directional light is present (z gate);
    // its shadow map darkens the lit term when active.
    if (frame.shadow_params.z > 0.5) {
        float3 l        = -normalize(frame.light_dir.xyz);
        float3 radiance = frame.light_color.rgb * frame.light_color.w;
        float  shadow   = (frame.shadow_params.x > 0.5) ? compute_shadow(input.world_pos) : 1.0;
        lit += pbr_direct(n, v, l, albedo_c, f0, metallic, rough, radiance) * shadow;
    }

    // Point lights — brute force, distance-attenuated (clamp(1 - d/radius)² from
    // the legacy bgfx path).
    uint pcount = (uint)frame.shadow_params.y;
    for (uint i = 0u; i < pcount; i++) {
        float3 to_l   = frame.point_lights[i].pos_radius.xyz - input.world_pos;
        float  dist   = length(to_l);
        float  radius = frame.point_lights[i].pos_radius.w;
        float3 l      = to_l / max(dist, 1e-4);
        float  att    = clamp(1.0 - dist / max(radius, 1e-4), 0.0, 1.0);
        att *= att;
        float3 radiance = frame.point_lights[i].color_intensity.rgb *
                          frame.point_lights[i].color_intensity.w * att;
        lit += pbr_direct(n, v, l, albedo_c, f0, metallic, rough, radiance);
    }

    // Image-based lighting — direct environment sampling (simple; the split-sum
    // approximation is deferred debt). Specular = env reflected off the surface,
    // diffuse = env at the normal. Env is a 1×1 black cube when no skybox is set.
    float3 f_ibl       = fresnel_schlick(max(dot(n, v), 0.0), f0);
    float3 ibl_spec    = env.Sample(env_sampler, reflect(-v, n)).rgb * f_ibl;
    float3 ibl_diffuse = env.Sample(env_sampler, n).rgb * albedo_c * (1.0 - metallic) * (1.0 - f_ibl);
    float3 ibl         = ibl_spec + ibl_diffuse;

    // Flat ambient is a diffuse fill (for scenes without an IBL environment); it
    // must not wash out metals, so gate it by (1 - metallic).
    float3 ambient = frame.ambient.rgb * albedo_c * (1.0 - metallic);
    float3 color   = ambient + lit + ibl;

    color = color / (color + 1.0);                       // Reinhard tonemap (transitional)
    color = pow(color, float3(1.0 / 2.2, 1.0 / 2.2, 1.0 / 2.2)); // linear -> display (UNORM swapchain)
    return float4(color, 1.0);
}
