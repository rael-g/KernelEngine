#ifndef KERNEL_ENGINE_ASSET_MESH_DATA_H_
#define KERNEL_ENGINE_ASSET_MESH_DATA_H_

#include <kernel_engine/render/mesh.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C"
{
#endif

    /// [view] Raw CPU-side mesh data returned by ke_asset_loader::load_model.
    ///        Vertices are ready to pass directly to ke_render::create_mesh.
    typedef struct ke_mesh_data
    {
        ke_vertex *vertices;   ///< [array_of:vertex_count] Vertices with pos, normal, UV, tangent
        uint32_t   vertex_count;
        uint16_t  *indices;    ///< [array_of:index_count] Triangle list indices (max 65535 vertices per mesh)
        uint32_t   index_count;
        int32_t    material_index; ///< Index into ke_model_data::materials; -1 = none
        char       name[64];
    } ke_mesh_data;

    /// [view] Raw CPU-side material data returned by ke_asset_loader::load_model.
    ///        Pass to ke_render::create_material after uploading textures.
    typedef struct ke_material_data
    {
        float   base_color_r, base_color_g, base_color_b, base_color_a;
        float   metallic;
        float   roughness;
        int32_t albedo_texture_index;     ///< Index into ke_model_data::textures; -1 = none
        int32_t normal_map_texture_index; ///< Index into ke_model_data::textures; -1 = none
        char    name[64];
    } ke_material_data;

    /// [view] Decoded RGBA8 texture data returned by ke_asset_loader::load_model.
    typedef struct ke_texture_data
    {
        uint8_t  *pixels;     ///< [array_of:byte_count] RGBA8 samples, row-major
        uint32_t  byte_count; ///< Bytes pixels reaches: width * height * 4
        uint32_t  width;
        uint32_t  height;
        char      path[256]; ///< Source path; empty for embedded textures
    } ke_texture_data;

    /// [view] Complete model data returned by ke_asset_loader::load_model.
    ///        Owned by the loader; free with ke_asset_loader::free_model.
    typedef struct ke_model_data
    {
        ke_mesh_data     *meshes;    ///< [array_of:mesh_count] Meshes the model is drawn from
        uint32_t          mesh_count;
        ke_material_data *materials; ///< [array_of:material_count] Materials the meshes index into
        uint32_t          material_count;
        ke_texture_data  *textures;  ///< [array_of:texture_count] Textures the materials index into
        uint32_t          texture_count;
    } ke_model_data;

#ifdef __cplusplus
}
#endif

#endif
