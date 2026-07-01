#include "assimp_converter.hpp"
#include "internal_helpers.hpp"
#include <assimp/mesh.h>
#include <assimp/material.h>
#include <assimp/scene.h>
#include <cstring>

namespace kernel_engine::asset::assimp::Converter
{

using namespace detail;

std::string GetDirectory(const char* path)
{
    std::string dir(path);
    auto slash = dir.find_last_of("/\\");
    if (slash != std::string::npos) return dir.substr(0, slash + 1);
    return "";
}

bool ConvertMesh(const aiMesh* am, ke_mesh_data* md)
{
    memset(md, 0, sizeof(ke_mesh_data));

    copy_string(md->name, sizeof(md->name), am->mName.C_Str());
    md->vertex_count = am->mNumVertices;
    md->index_count  = am->mNumFaces * 3;

    // Allocate vertex buffer
    md->vertices = (ke_vertex *)ke_alloc(sizeof(ke_vertex) * am->mNumVertices, alignof(ke_vertex));
    if (!md->vertices) return false;

    // Allocate index buffer
    md->indices = (uint16_t *)ke_alloc(sizeof(uint16_t) * md->index_count, alignof(uint16_t));
    if (!md->indices)
    {
        ke_free(md->vertices);
        return false;
    }

    // Fill vertices
    for (uint32_t vi = 0; vi < am->mNumVertices; ++vi)
    {
        ke_vertex &v = md->vertices[vi];
        v.x = am->mVertices[vi].x;
        v.y = am->mVertices[vi].y;
        v.z = am->mVertices[vi].z;

        if (am->HasNormals())
        {
            v.nx = am->mNormals[vi].x;
            v.ny = am->mNormals[vi].y;
            v.nz = am->mNormals[vi].z;
        }
        else { v.nx = 0.f; v.ny = 0.f; v.nz = 1.f; }

        if (am->HasTextureCoords(0))
        {
            v.u = am->mTextureCoords[0][vi].x;
            v.v = am->mTextureCoords[0][vi].y;
        }
        else { v.u = 0.f; v.v = 0.f; }

        if (am->HasTangentsAndBitangents())
        {
            const aiVector3D &T = am->mTangents[vi];
            const aiVector3D &B = am->mBitangents[vi];
            const aiVector3D &N = am->mNormals[vi];
            v.tx = T.x; v.ty = T.y; v.tz = T.z;

            float cx = N.y * T.z - N.z * T.y;
            float cy = N.z * T.x - N.x * T.z;
            float cz = N.x * T.y - N.y * T.x;
            v.tw = (cx * B.x + cy * B.y + cz * B.z >= 0.f) ? 1.f : -1.f;
        }
        else
        {
            // Compute a tangent perpendicular to the vertex normal.
            // Cross with world-up; fall back to world-right for near-vertical normals.
            // Use the normal already resolved above (v.n*), which defaults to
            // (0,0,1) when the mesh carries no normals — reading am->mNormals here
            // would dereference null for a normal-less mesh.
            aiVector3D N(v.nx, v.ny, v.nz);
            aiVector3D up(0.f, 1.f, 0.f);
            float dot_up = N.x * up.x + N.y * up.y + N.z * up.z;
            if (dot_up > 0.9f || dot_up < -0.9f)
                up = aiVector3D(0.f, 0.f, 1.f);
            aiVector3D t;
            dot_up = N.x * up.x + N.y * up.y + N.z * up.z;
            t.x = up.x - N.x * dot_up;
            t.y = up.y - N.y * dot_up;
            t.z = up.z - N.z * dot_up;
            float len = sqrtf(t.x * t.x + t.y * t.y + t.z * t.z);
            if (len > 1e-4f) { t.x /= len; t.y /= len; t.z /= len; }
            else              { t = aiVector3D(1.f, 0.f, 0.f); }
            v.tx = t.x; v.ty = t.y; v.tz = t.z; v.tw = 1.f;
        }
    }

    // Fill indices
    uint32_t idx_cursor = 0;
    for (uint32_t fi = 0; fi < am->mNumFaces; ++fi)
    {
        const aiFace &face = am->mFaces[fi];
        for (uint32_t j = 0; j < 3 && j < face.mNumIndices; ++j)
            md->indices[idx_cursor++] = (uint16_t)face.mIndices[j];
    }
    md->index_count = idx_cursor;

    return true;
}

bool ConvertMaterial(const aiMaterial* am, ke_material_data* md, int32_t* albedo_index, int32_t* normal_index)
{
    memset(md, 0, sizeof(ke_material_data));

    // Name
    aiString name;
    if (am->Get(AI_MATKEY_NAME, name) == AI_SUCCESS)
        copy_string(md->name, sizeof(md->name), name.C_Str());

    // Base color
    aiColor4D color(1.f, 1.f, 1.f, 1.f);
    if (am->Get(AI_MATKEY_BASE_COLOR, color) != AI_SUCCESS)
        am->Get(AI_MATKEY_COLOR_DIFFUSE, color);
    
    md->base_color_r = color.r; 
    md->base_color_g = color.g;
    md->base_color_b = color.b; 
    md->base_color_a = color.a;

    float metallic = 0.f, roughness = 0.5f;
    am->Get(AI_MATKEY_METALLIC_FACTOR, metallic);
    am->Get(AI_MATKEY_ROUGHNESS_FACTOR, roughness);
    md->metallic  = metallic;
    md->roughness = roughness;

    return true;
}

} // namespace kernel_engine::asset::assimp::Converter
