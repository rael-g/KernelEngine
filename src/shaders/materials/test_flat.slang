// test_flat.slang — minimal IMaterial: solid colour, no deformations.
import ke;

struct TestFlat : IMaterial {
    float3 colorTint;

    void vertex(inout VertexInfo v) {
        // no deformation — default pass transform is sufficient
    }

    void fragment(inout SurfaceState s) {
        s.albedo   = colorTint;
        s.metallic = 0.0;
        s.roughness = 0.5;
        s.ao       = 1.0;
        s.alpha    = 1.0;
    }
};

// ── Entry points (manifest-generated in production) ──

TestFlat _mat;

[shader("vertex")]
VertexInfo vs_main(VertexInfo v) { _mat.vertex(v); return v; }

[shader("fragment")]
SurfaceState fs_main(SurfaceState s) { _mat.fragment(s); return s; }
