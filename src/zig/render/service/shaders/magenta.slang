// Magenta placeholder — Mechanism 1 "never silent" fallback (§6). Drawn for a
// mesh whose requested material PSO is missing (e.g. an unassigned material
// handle). Same vertex layout + pipeline layout as the mesh-drawing passes so
// the draw loop binds it uniformly; the fragment just outputs solid magenta so
// the miss is obvious and debuggable rather than silently wrong.

struct VsIn {
    float3 position : POSITION;
    float3 normal   : NORMAL;
    float2 uv       : TEXCOORD0;
    float3 tangent  : TANGENT;
};
struct VsOut {
    float4 clip : SV_Position;
};

struct PerObject {
    float4x4 mvp;
    float4x4 model;
};
[[vk::binding(0, 2)]] ConstantBuffer<PerObject> obj;

[shader("vertex")]
VsOut vs_main(VsIn input) {
    VsOut o;
    o.clip = mul(obj.mvp, float4(input.position, 1.0));
    return o;
}

[shader("fragment")]
float4 fs_main(VsOut input) : SV_Target {
    return float4(1.0, 0.0, 1.0, 1.0);
}
