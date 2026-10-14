import ke;
__exported import forward_common;
import shadow_feature;
import ibl_feature;
import cluster_feature;
import refraction_feature;

struct PerFrame {
    float4   camera_pos;
    float4   light_dir;
    float4   light_color;
    float4   ambient;
    float4   shadow_params;
    float4   viewport;
    float4x4 view;
};
[[vk::binding(0, 0)]] ConstantBuffer<PerFrame> frame;

float4 ke_transparent_fs<T : IMaterial>(T material, VsOut input) {
    SurfaceState s = ke_surface_from_vertex(material, input);

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

    float view_z = mul(frame.view, float4(input.world_pos, 1.0)).z;
    lit += accumulate_clustered_lights(n, v, albedo_c, f0, metallic, rough, input.world_pos, input.clip.xy, view_z);

    float3 ibl = ibl_contribution(n, v, albedo_c, metallic);

    float3 ambient = frame.ambient.rgb * albedo_c * (1.0 - metallic);
    float3 color   = ambient + lit + s.emissive + ibl;

    float3 refr = refraction_contribution(n, v, input.clip.xy / frame.viewport.xy, mat.ior, mat.distortion_strength);
    color = lerp(refr, color, s.alpha);

    return float4(color, s.alpha);
}
