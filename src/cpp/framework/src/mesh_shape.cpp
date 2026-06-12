// CPU-side primitive mesh baking for the framework asset path. Pure math; no
// GPU interaction. The output buffers are owned by the caller via the supplied
// ke_allocator — pair every bake with a ke_mesh_shape_free.

#include <kernel_engine/kernel/framework/mesh_shape.h>

#include <cmath>
#include <cstring>

namespace
{

constexpr float kPi = 3.14159265358979323846f;

// Writes a single vertex into out[i] at packed layout.
inline void set_vertex(ke_vertex &v,
                       float x, float y, float z,
                       float nx, float ny, float nz,
                       float u, float vc,
                       float tx, float ty, float tz, float tw)
{
    v.x = x; v.y = y; v.z = z;
    v.nx = nx; v.ny = ny; v.nz = nz;
    v.u = u; v.v = vc;
    v.tx = tx; v.ty = ty; v.tz = tz; v.tw = tw;
}

// ── Quad / Plane shared helper ──────────────────────────────────────────────

void bake_quad_like(ke_vertex *vtx, uint16_t *idx,
                    float nx, float ny, float nz,
                    float tx, float ty, float tz,
                    float p0x, float p0y, float p0z,
                    float p1x, float p1y, float p1z,
                    float p2x, float p2y, float p2z,
                    float p3x, float p3y, float p3z)
{
    set_vertex(vtx[0], p0x, p0y, p0z, nx, ny, nz, 0, 0, tx, ty, tz, 1);
    set_vertex(vtx[1], p1x, p1y, p1z, nx, ny, nz, 1, 0, tx, ty, tz, 1);
    set_vertex(vtx[2], p2x, p2y, p2z, nx, ny, nz, 1, 1, tx, ty, tz, 1);
    set_vertex(vtx[3], p3x, p3y, p3z, nx, ny, nz, 0, 1, tx, ty, tz, 1);
    idx[0] = 0; idx[1] = 1; idx[2] = 2;
    idx[3] = 0; idx[4] = 2; idx[5] = 3;
}

// ── Cube ────────────────────────────────────────────────────────────────────

void bake_cube(ke_vertex *vtx, uint16_t *idx)
{
    struct Face { float nx, ny, nz, tx, ty, tz, p[4][3]; };
    const Face faces[6] = {
        // +X
        { 1, 0, 0,  0, 0, -1, {{ 0.5f,-0.5f, 0.5f},{ 0.5f,-0.5f,-0.5f},{ 0.5f, 0.5f,-0.5f},{ 0.5f, 0.5f, 0.5f}}},
        // -X
        {-1, 0, 0,  0, 0,  1, {{-0.5f,-0.5f,-0.5f},{-0.5f,-0.5f, 0.5f},{-0.5f, 0.5f, 0.5f},{-0.5f, 0.5f,-0.5f}}},
        // +Y
        { 0, 1, 0,  1, 0,  0, {{-0.5f, 0.5f, 0.5f},{ 0.5f, 0.5f, 0.5f},{ 0.5f, 0.5f,-0.5f},{-0.5f, 0.5f,-0.5f}}},
        // -Y
        { 0,-1, 0,  1, 0,  0, {{-0.5f,-0.5f,-0.5f},{ 0.5f,-0.5f,-0.5f},{ 0.5f,-0.5f, 0.5f},{-0.5f,-0.5f, 0.5f}}},
        // +Z
        { 0, 0, 1,  1, 0,  0, {{-0.5f,-0.5f, 0.5f},{ 0.5f,-0.5f, 0.5f},{ 0.5f, 0.5f, 0.5f},{-0.5f, 0.5f, 0.5f}}},
        // -Z
        { 0, 0,-1, -1, 0,  0, {{ 0.5f,-0.5f,-0.5f},{-0.5f,-0.5f,-0.5f},{-0.5f, 0.5f,-0.5f},{ 0.5f, 0.5f,-0.5f}}},
    };

    for (uint16_t f = 0; f < 6; ++f) {
        const Face &face = faces[f];
        uint16_t base = static_cast<uint16_t>(f * 4);
        set_vertex(vtx[base + 0], face.p[0][0], face.p[0][1], face.p[0][2],
                   face.nx, face.ny, face.nz, 0, 0, face.tx, face.ty, face.tz, 1);
        set_vertex(vtx[base + 1], face.p[1][0], face.p[1][1], face.p[1][2],
                   face.nx, face.ny, face.nz, 1, 0, face.tx, face.ty, face.tz, 1);
        set_vertex(vtx[base + 2], face.p[2][0], face.p[2][1], face.p[2][2],
                   face.nx, face.ny, face.nz, 1, 1, face.tx, face.ty, face.tz, 1);
        set_vertex(vtx[base + 3], face.p[3][0], face.p[3][1], face.p[3][2],
                   face.nx, face.ny, face.nz, 0, 1, face.tx, face.ty, face.tz, 1);

        uint32_t ii = f * 6;
        idx[ii + 0] = base;
        idx[ii + 1] = static_cast<uint16_t>(base + 1);
        idx[ii + 2] = static_cast<uint16_t>(base + 2);
        idx[ii + 3] = base;
        idx[ii + 4] = static_cast<uint16_t>(base + 2);
        idx[ii + 5] = static_cast<uint16_t>(base + 3);
    }
}

// ── Sphere ──────────────────────────────────────────────────────────────────

uint32_t sphere_vertex_count(uint32_t segments, uint32_t rings)
{
    return (rings + 1) * (segments + 1);
}

uint32_t sphere_index_count(uint32_t segments, uint32_t rings)
{
    return rings * segments * 6;
}

void bake_sphere(ke_vertex *vtx, uint16_t *idx, uint32_t segments, uint32_t rings)
{
    uint32_t v = 0;
    for (uint32_t r = 0; r <= rings; ++r) {
        float phi = kPi * static_cast<float>(r) / static_cast<float>(rings);
        float y = std::cos(phi);
        float sin_phi = std::sin(phi);
        for (uint32_t s = 0; s <= segments; ++s) {
            float theta = 2.0f * kPi * static_cast<float>(s) / static_cast<float>(segments);
            float x  = sin_phi * std::cos(theta);
            float z  = sin_phi * std::sin(theta);
            float tx = -std::sin(theta);
            float tz =  std::cos(theta);
            set_vertex(vtx[v], x * 0.5f, y * 0.5f, z * 0.5f, x, y, z,
                       static_cast<float>(s) / static_cast<float>(segments),
                       static_cast<float>(r) / static_cast<float>(rings),
                       tx, 0.0f, tz, 1.0f);
            ++v;
        }
    }

    uint32_t i = 0;
    uint32_t row = segments + 1;
    for (uint32_t r = 0; r < rings; ++r) {
        for (uint32_t s = 0; s < segments; ++s) {
            uint16_t a = static_cast<uint16_t>(r * row + s);
            uint16_t b = static_cast<uint16_t>(a + row);
            uint16_t c = static_cast<uint16_t>(a + 1);
            uint16_t d = static_cast<uint16_t>(b + 1);
            idx[i++] = a; idx[i++] = b; idx[i++] = c;
            idx[i++] = c; idx[i++] = b; idx[i++] = d;
        }
    }
}

} // namespace

// ── Public API ──────────────────────────────────────────────────────────────

extern "C" ke_result ke_mesh_shape_bake(
    ke_allocator       *alloc,
    ke_mesh_primitive   prim,
    uint32_t            segments,
    ke_mesh_shape_data *out_data)
{
    if (!alloc || !out_data) return KE_ERROR_INVALID_ARGUMENT;
    std::memset(out_data, 0, sizeof(*out_data));

    uint32_t vcount = 0, icount = 0;
    uint32_t rings  = 0;
    switch (prim) {
    case KE_MESH_PRIMITIVE_QUAD:
    case KE_MESH_PRIMITIVE_PLANE:
        vcount = 4;
        icount = 6;
        break;
    case KE_MESH_PRIMITIVE_CUBE:
        vcount = 24;
        icount = 36;
        break;
    case KE_MESH_PRIMITIVE_SPHERE:
        if (segments == 0) segments = 32;
        if (segments < 3)  segments = 3;
        rings  = segments / 2;
        if (rings < 2)     rings    = 2;
        vcount = sphere_vertex_count(segments, rings);
        icount = sphere_index_count(segments, rings);
        break;
    default:
        return KE_ERROR_INVALID_ARGUMENT;
    }

    auto *vbuf = static_cast<ke_vertex *>(
        alloc->alloc(alloc, sizeof(ke_vertex) * vcount, alignof(ke_vertex)));
    if (!vbuf) return KE_ERROR_OUT_OF_MEMORY;
    auto *ibuf = static_cast<uint16_t *>(
        alloc->alloc(alloc, sizeof(uint16_t) * icount, alignof(uint16_t)));
    if (!ibuf) {
        alloc->free(alloc, vbuf);
        return KE_ERROR_OUT_OF_MEMORY;
    }

    switch (prim) {
    case KE_MESH_PRIMITIVE_QUAD:
        bake_quad_like(vbuf, ibuf, 0, 0, 1, 1, 0, 0,
                       -0.5f, -0.5f, 0,   0.5f, -0.5f, 0,
                        0.5f,  0.5f, 0,  -0.5f,  0.5f, 0);
        break;
    case KE_MESH_PRIMITIVE_PLANE:
        bake_quad_like(vbuf, ibuf, 0, 1, 0, 1, 0, 0,
                       -0.5f, 0,  0.5f,   0.5f, 0,  0.5f,
                        0.5f, 0, -0.5f,  -0.5f, 0, -0.5f);
        break;
    case KE_MESH_PRIMITIVE_CUBE:
        bake_cube(vbuf, ibuf);
        break;
    case KE_MESH_PRIMITIVE_SPHERE:
        bake_sphere(vbuf, ibuf, segments, rings);
        break;
    default:
        // unreachable — guarded above
        alloc->free(alloc, vbuf);
        alloc->free(alloc, ibuf);
        return KE_ERROR_INVALID_ARGUMENT;
    }

    out_data->vertices     = vbuf;
    out_data->vertex_count = vcount;
    out_data->indices      = ibuf;
    out_data->index_count  = icount;
    return KE_OK;
}

extern "C" void ke_mesh_shape_free(ke_allocator *alloc, ke_mesh_shape_data *data)
{
    if (!alloc || !data) return;
    if (data->vertices) alloc->free(alloc, data->vertices);
    if (data->indices)  alloc->free(alloc, data->indices);
    data->vertices     = nullptr;
    data->indices      = nullptr;
    data->vertex_count = 0;
    data->index_count  = 0;
}
