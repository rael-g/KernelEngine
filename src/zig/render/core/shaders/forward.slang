// Forward PBR (Cook-Torrance GGX metallic-roughness) with a single directional
// light. Descriptor sets split by update frequency (Vulkan/WebGPU convention):
// set 0 = per-frame (camera + light), set 1 = per-material (glTF base color +
// metallic/roughness + albedo), set 2 = per-object (transform, dynamic offset).
// Matrices arrive row-major (row-vector convention) so Slang's mul(M, v) lowers
// to WGSL correctly. Inline Reinhard + gamma is transitional until the tonemap
// pass (example 10) owns it.

struct VsIn {
    float3 position : POSITION;
    float3 normal   : NORMAL;
    float2 uv       : TEXCOORD0;
};

struct VsOut {
    float4 clip : SV_Position;
    [[vk::location(0)]] float3 world_normal : NORMAL;
    [[vk::location(1)]] float3 world_pos    : POSITION;
    [[vk::location(2)]] float2 uv           : TEXCOORD0;
};

// Set 0 — per frame: camera + single directional light.
struct PerFrame {
    float4 camera_pos;  // xyz
    float4 light_dir;   // xyz = direction the light travels (normalized)
    float4 light_color; // rgb, w = intensity
    float4 ambient;     // rgb
};
[[vk::binding(0, 0)]] ConstantBuffer<PerFrame> frame;

// Set 1 — per material: glTF metallic-roughness.
struct Material {
    float4 base_color;
    float  metallic;
    float  roughness;
    float2 _pad;
};
[[vk::binding(0, 1)]] ConstantBuffer<Material> mat;
[[vk::binding(1, 1)]] Texture2D    albedo;
[[vk::binding(2, 1)]] SamplerState albedo_sampler;

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

[shader("vertex")]
VsOut vs_main(VsIn input) {
    VsOut o;
    o.clip         = mul(obj.mvp, float4(input.position, 1.0));
    o.world_normal = mul((float3x3)obj.model, input.normal);
    o.world_pos    = mul(obj.model, float4(input.position, 1.0)).xyz;
    o.uv           = input.uv;
    return o;
}

[shader("fragment")]
float4 fs_main(VsOut input) : SV_Target {
    float3 albedo_c = mat.base_color.rgb * albedo.Sample(albedo_sampler, input.uv).rgb;
    float  metallic = mat.metallic;
    float  rough    = mat.roughness;

    float3 n = normalize(input.world_normal);
    float3 v = normalize(frame.camera_pos.xyz - input.world_pos);
    float3 l = -normalize(frame.light_dir.xyz);
    float3 h = normalize(v + l);

    float3 radiance = frame.light_color.rgb * frame.light_color.w;
    float3 f0 = lerp(float3(0.04, 0.04, 0.04), albedo_c, metallic);

    float  ndf = distribution_ggx(n, h, rough);
    float  g   = geometry_smith(n, v, l, rough);
    float3 f   = fresnel_schlick(max(dot(h, v), 0.0), f0);

    float3 specular = (ndf * g * f) / (4.0 * max(dot(n, v), 0.0) * max(dot(n, l), 0.0) + 1e-4);
    float3 kd = (float3(1.0, 1.0, 1.0) - f) * (1.0 - metallic);
    float  ndotl = max(dot(n, l), 0.0);

    float3 diffuse = kd * albedo_c / PI;
    float3 lit     = (diffuse + specular) * radiance * ndotl;
    float3 ambient = frame.ambient.rgb * albedo_c;
    float3 color   = ambient + lit;

    color = color / (color + 1.0);                       // Reinhard tonemap (transitional)
    color = pow(color, float3(1.0 / 2.2, 1.0 / 2.2, 1.0 / 2.2)); // linear -> display (UNORM swapchain)
    return float4(color, 1.0);
}
