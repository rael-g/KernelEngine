import ke;
__exported import forward_common;
import gbuffer_encoding;

struct GBufferOut {
    float4 rt0 : SV_Target0;
    float4 rt1 : SV_Target1;
    float4 rt2 : SV_Target2;
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
