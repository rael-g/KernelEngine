#pragma once

#include <kernel_engine/allocator/allocator.h>
#include <kernel_engine/asset/asset_loader.h>
#include <string>

struct aiMesh;
struct aiMaterial;
struct aiScene;

namespace kernel_engine::asset::assimp::Converter
{

std::string GetDirectory(const char* path);

ke_result ConvertMesh(const aiMesh* ai_mesh, ke_allocator* allocator, ke_mesh_data* out_mesh);
ke_result ConvertMaterial(const aiMaterial* ai_mat, ke_material_data* out_mat, int32_t* albedo_index, int32_t* normal_index);

} // namespace kernel_engine::asset::assimp::Converter
