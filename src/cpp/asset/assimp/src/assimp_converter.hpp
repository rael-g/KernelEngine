#pragma once

#include <kernel_engine/asset/asset_loader.h>
#include <string>

struct aiMesh;
struct aiMaterial;
struct aiScene;

namespace kernel_engine::asset::assimp::Converter
{

std::string GetDirectory(const char* path);

bool ConvertMesh(const aiMesh* ai_mesh, ke_mesh_data* out_mesh);
bool ConvertMaterial(const aiMaterial* ai_mat, ke_material_data* out_mat, int32_t* albedo_index, int32_t* normal_index);

} // namespace kernel_engine::asset::assimp::Converter
