// Deferred G-buffer encode pass, generic over IMaterial. Runs the same vertex
// transform + material.fragment() as the forward pass (via forward_common), but
// instead of shading inline it packs the resulting SurfaceState into the
// G-buffer's render targets — the deferred-lighting pass decodes + shades them
// later. No lighting math here at all.
//
// Target layout (must match deferred_lighting.slang's decode):
//   RT0 RGBA8:   albedo.rgb, metallic
//   RT1 RGBA8:   octNormal.xy, roughness, ao
//   RT2 RGBA16F: emissive.rgb, alpha
// Position is NOT stored — deferred reconstructs it from the depth buffer.

import ke;
__exported import forward_common; // VsIn/VsOut + ke_forward_vs / ke_surface_from_vertex
import gbuffer_encoding;           // ke_oct_encode

struct GBufferOut {
    float4 rt0 : SV_Target0; // albedo.rgb, metallic
    float4 rt1 : SV_Target1; // octNormal.xy, roughness, ao
    float4 rt2 : SV_Target2; // emissive.rgb, alpha
};

GBufferOut ke_gbuffer_fs<T : IMaterial>(T material, VsOut input) {
    SurfaceState s = ke_surface_from_vertex(material, input);
    float2 oct = ke_oct_encode(normalize(s.normal));
    GBufferOut o;
    o.rt0 = float4(s.albedo, s.metallic);
    o.rt1 = float4(oct, s.roughness, s.ao);
    o.rt2 = float4(s.emissive, s.alpha);
    return o;
}
