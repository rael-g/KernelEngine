#ifndef KERNEL_ENGINE_ASSET_VERTEX_H_
#define KERNEL_ENGINE_ASSET_VERTEX_H_

#ifdef __cplusplus
extern "C"
{
#endif

    /// [value] Per-vertex data of a mesh, as authored.
    typedef struct ke_vertex
    {
        float x, y, z;       ///< Object-space position
        float nx, ny, nz;    ///< Object-space normal (normalized)
        float u, v;          ///< UV texture coordinates
        float tx, ty, tz;    ///< Object-space tangent (normalized)
        float tw;            ///< Bitangent sign: +1 or -1 (bitangent = cross(N,T)*tw)
    } ke_vertex;

#ifdef __cplusplus
}
#endif

#endif
