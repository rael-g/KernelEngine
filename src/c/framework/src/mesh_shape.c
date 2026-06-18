// CPU-side primitive mesh baking — pure math. Internal to the framework
// plugin (see mesh_shape_internal.h). External callers reach these through
// ke_asset_resolver->resolve_mesh.

#include "mesh_shape_internal.h"
#include <kernel_engine/allocator/allocator.h>

#include <math.h>
#include <stdalign.h>
#include <stddef.h>
#include <string.h>

static const float kPi = 3.14159265358979323846f;

static void set_vertex(ke_vertex *v,
                       float x, float y, float z,
                       float nx, float ny, float nz,
                       float u, float vc,
                       float tx, float ty, float tz, float tw) {
    v->x = x; v->y = y; v->z = z;
    v->nx = nx; v->ny = ny; v->nz = nz;
    v->u = u; v->v = vc;
    v->tx = tx; v->ty = ty; v->tz = tz; v->tw = tw;
}

static void bake_quad_like(ke_vertex *vtx, uint16_t *idx,
                            float nx, float ny, float nz,
                            float tx, float ty, float tz,
                            float p0x, float p0y, float p0z,
                            float p1x, float p1y, float p1z,
                            float p2x, float p2y, float p2z,
                            float p3x, float p3y, float p3z) {
    set_vertex(&vtx[0], p0x, p0y, p0z, nx, ny, nz, 0, 0, tx, ty, tz, 1);
    set_vertex(&vtx[1], p1x, p1y, p1z, nx, ny, nz, 1, 0, tx, ty, tz, 1);
    set_vertex(&vtx[2], p2x, p2y, p2z, nx, ny, nz, 1, 1, tx, ty, tz, 1);
    set_vertex(&vtx[3], p3x, p3y, p3z, nx, ny, nz, 0, 1, tx, ty, tz, 1);
    idx[0] = 0; idx[1] = 1; idx[2] = 2;
    idx[3] = 0; idx[4] = 2; idx[5] = 3;
}

typedef struct CubeFace {
    float nx, ny, nz;
    float tx, ty, tz;
    float p[4][3];
} CubeFace;

static const CubeFace kCubeFaces[6] = {
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

static void bake_cube(ke_vertex *vtx, uint16_t *idx) {
    for (uint16_t f = 0; f < 6; ++f) {
        const CubeFace *face = &kCubeFaces[f];
        uint16_t base = (uint16_t)(f * 4);
        set_vertex(&vtx[base + 0], face->p[0][0], face->p[0][1], face->p[0][2],
                   face->nx, face->ny, face->nz, 0, 0, face->tx, face->ty, face->tz, 1);
        set_vertex(&vtx[base + 1], face->p[1][0], face->p[1][1], face->p[1][2],
                   face->nx, face->ny, face->nz, 1, 0, face->tx, face->ty, face->tz, 1);
        set_vertex(&vtx[base + 2], face->p[2][0], face->p[2][1], face->p[2][2],
                   face->nx, face->ny, face->nz, 1, 1, face->tx, face->ty, face->tz, 1);
        set_vertex(&vtx[base + 3], face->p[3][0], face->p[3][1], face->p[3][2],
                   face->nx, face->ny, face->nz, 0, 1, face->tx, face->ty, face->tz, 1);

        uint32_t ii = f * 6;
        idx[ii + 0] = base;
        idx[ii + 1] = (uint16_t)(base + 1);
        idx[ii + 2] = (uint16_t)(base + 2);
        idx[ii + 3] = base;
        idx[ii + 4] = (uint16_t)(base + 2);
        idx[ii + 5] = (uint16_t)(base + 3);
    }
}

static uint32_t sphere_vertex_count(uint32_t segments, uint32_t rings) {
    return (rings + 1) * (segments + 1);
}

static uint32_t sphere_index_count(uint32_t segments, uint32_t rings) {
    return rings * segments * 6;
}

static void bake_sphere(ke_vertex *vtx, uint16_t *idx, uint32_t segments, uint32_t rings) {
    uint32_t v = 0;
    for (uint32_t r = 0; r <= rings; ++r) {
        float phi = kPi * (float)r / (float)rings;
        float y = cosf(phi);
        float sin_phi = sinf(phi);
        for (uint32_t s = 0; s <= segments; ++s) {
            float theta = 2.0f * kPi * (float)s / (float)segments;
            float x  = sin_phi * cosf(theta);
            float z  = sin_phi * sinf(theta);
            float tx = -sinf(theta);
            float tz =  cosf(theta);
            set_vertex(&vtx[v], x * 0.5f, y * 0.5f, z * 0.5f, x, y, z,
                       (float)s / (float)segments,
                       (float)r / (float)rings,
                       tx, 0.0f, tz, 1.0f);
            ++v;
        }
    }

    uint32_t i = 0;
    uint32_t row = segments + 1;
    for (uint32_t r = 0; r < rings; ++r) {
        for (uint32_t s = 0; s < segments; ++s) {
            uint16_t a = (uint16_t)(r * row + s);
            uint16_t b = (uint16_t)(a + row);
            uint16_t c = (uint16_t)(a + 1);
            uint16_t d = (uint16_t)(b + 1);
            idx[i++] = a; idx[i++] = b; idx[i++] = c;
            idx[i++] = c; idx[i++] = b; idx[i++] = d;
        }
    }
}

ke_result ke_mesh_shape_bake_internal(ke_mesh_primitive prim,
                                       uint32_t segments, ke_mesh_shape_data *out_data) {
    if (!out_data) return KE_ERROR;
    memset(out_data, 0, sizeof(*out_data));

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
        return KE_ERROR;
    }

    ke_vertex *vbuf = (ke_vertex *)ke_alloc(sizeof(ke_vertex) * vcount, alignof(ke_vertex));
    if (!vbuf) return KE_ERROR;
    uint16_t *ibuf = (uint16_t *)ke_alloc(sizeof(uint16_t) * icount, alignof(uint16_t));
    if (!ibuf) {
        ke_free(vbuf);
        return KE_ERROR;
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
        ke_free(vbuf);
        ke_free(ibuf);
        return KE_ERROR;
    }

    out_data->vertices     = vbuf;
    out_data->vertex_count = vcount;
    out_data->indices      = ibuf;
    out_data->index_count  = icount;
    return KE_OK;
}

void ke_mesh_shape_free_internal(ke_mesh_shape_data *data) {
    if (!data) return;
    if (data->vertices) ke_free(data->vertices);
    if (data->indices)  ke_free(data->indices);
    data->vertices     = NULL;
    data->indices      = NULL;
    data->vertex_count = 0;
    data->index_count  = 0;
}
