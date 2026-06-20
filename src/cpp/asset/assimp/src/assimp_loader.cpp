#include "assimp_loader.hpp"
#include "assimp_converter.hpp"
#include "texture_decoder.hpp"
#include "internal_helpers.hpp"
#include <kernel_engine/common/error.h>
#include <kernel_engine/allocator/allocator.h>

#include <assimp/Importer.hpp>
#include <assimp/scene.h>
#include <assimp/postprocess.h>
#include <unordered_map>
#include <vector>
#include <string>
#include <new>

namespace kernel_engine::asset::assimp
{

using namespace detail;

AssimpLoader::AssimpLoader(const ke_asset_loader_assimp_params *params)
    : logger_(params->logger)
{
    api_.handle     = this;
    api_.load_model = [](ke_asset_loader *self, const char *path, ke_error **out_error) -> ke_model_data * {
        return static_cast<AssimpLoader *>(self->handle)->LoadModel(path, out_error);
    };
    api_.free_model = [](ke_asset_loader *self, ke_model_data *data) {
        static_cast<AssimpLoader *>(self->handle)->FreeModel(data);
    };
    api_.load_model_async = [](ke_asset_loader *self,
                                ke_scheduler *scheduler,
                                const char *path,
                                ke_load_model_complete_func on_complete,
                                void *user_data) -> ke_task * {
        if (!self || !self->handle) return nullptr;
        return static_cast<AssimpLoader *>(self->handle)->LoadModelAsync(
            scheduler, path, on_complete, user_data);
    };
}

AssimpLoader::~AssimpLoader() = default;

ke_asset_loader *AssimpLoader::ToApi() { return &api_; }

void AssimpLoader::DestroyApi(ke_asset_loader *self)
{
    auto *l = static_cast<AssimpLoader *>(self->handle);
    l->~AssimpLoader();
    ke_free(l);
}

ke_model_data *AssimpLoader::LoadModel(const char *path, ke_error **out_error)
{
    if (!path)
    {
        KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
        return nullptr;
    }

    Assimp::Importer importer;
    importer.SetPropertyInteger(AI_CONFIG_PP_SLM_VERTEX_LIMIT, 65534);

    const aiScene *scene = importer.ReadFile(path,
        aiProcess_Triangulate          |
        aiProcess_GenSmoothNormals     |
        aiProcess_CalcTangentSpace     |
        aiProcess_JoinIdenticalVertices|
        aiProcess_FlipUVs              |
        aiProcess_SortByPType          |
        aiProcess_SplitLargeMeshes);

    if (!scene || !scene->mRootNode || (scene->mFlags & AI_SCENE_FLAGS_INCOMPLETE))
    {
        LogErr(logger_, false, "LoadModel", importer.GetErrorString());
        KE_ERROR_SET(out_error, &KE_ERROR_IO, importer.GetErrorString());
        return nullptr;
    }

    std::string dir = Converter::GetDirectory(path);

    // ── Unique Texture Collection ───────────────────────────────────────────
    std::unordered_map<std::string, uint32_t> tex_index_map;
    std::vector<const aiTexture *> embedded_refs;
    std::vector<std::string>       external_paths;
    std::vector<bool>              is_embedded;

    auto register_texture = [&](const aiMaterial *mat, aiTextureType type) -> int32_t {
        aiString tex_path;
        if (mat->GetTexture(type, 0, &tex_path) != AI_SUCCESS) return -1;
        std::string key(tex_path.C_Str());
        auto it = tex_index_map.find(key);
        if (it != tex_index_map.end()) return (int32_t)it->second;

        uint32_t idx = (uint32_t)tex_index_map.size();
        tex_index_map[key] = idx;

        if (key[0] == '*') {
            uint32_t embedded_idx = (uint32_t)std::stoul(key.substr(1));
            embedded_refs.push_back(embedded_idx < scene->mNumTextures ? scene->mTextures[embedded_idx] : nullptr);
            external_paths.push_back("");
            is_embedded.push_back(true);
        } else {
            embedded_refs.push_back(nullptr);
            external_paths.push_back(dir + key);
            is_embedded.push_back(false);
        }
        return (int32_t)idx;
    };

    // ── Build Materials ─────────────────────────────────────────────────────
    uint32_t mat_count = scene->mNumMaterials;
    std::vector<ke_material_data> mats(mat_count);
    std::vector<int32_t> albedo_indices(mat_count, -1);
    std::vector<int32_t> normal_indices(mat_count, -1);

    for (uint32_t mi = 0; mi < mat_count; ++mi) {
        const aiMaterial *am = scene->mMaterials[mi];
        Converter::ConvertMaterial(am, &mats[mi], nullptr, nullptr);
        
        albedo_indices[mi] = register_texture(am, aiTextureType_BASE_COLOR);
        if (albedo_indices[mi] < 0) albedo_indices[mi] = register_texture(am, aiTextureType_DIFFUSE);
        
        normal_indices[mi] = register_texture(am, aiTextureType_NORMALS);
        if (normal_indices[mi] < 0) normal_indices[mi] = register_texture(am, aiTextureType_HEIGHT);
    }

    // ── Decode Textures ─────────────────────────────────────────────────────
    uint32_t tex_count = (uint32_t)tex_index_map.size();
    std::vector<ke_texture_data> texs(tex_count);
    for (uint32_t ti = 0; ti < tex_count; ti++) {
        if (is_embedded[ti] && embedded_refs[ti]) {
            TextureDecoder::DecodeEmbedded(embedded_refs[ti], logger_, &texs[ti]);
        } else {
            TextureDecoder::DecodeExternal(external_paths[ti], logger_, &texs[ti]);
        }
    }

    // Patch indices
    for (uint32_t mi = 0; mi < mat_count; ++mi) {
        mats[mi].albedo_texture_index     = albedo_indices[mi];
        mats[mi].normal_map_texture_index = normal_indices[mi];
    }

    // ── Build Meshes ────────────────────────────────────────────────────────
    uint32_t mesh_count = scene->mNumMeshes;
    std::vector<ke_mesh_data> meshes(mesh_count);
    for (uint32_t si = 0; si < mesh_count; si++) {
        Converter::ConvertMesh(scene->mMeshes[si], &meshes[si]);
        meshes[si].material_index = (scene->mMeshes[si]->mMaterialIndex < mat_count) 
                                    ? (int32_t)scene->mMeshes[si]->mMaterialIndex : -1;
    }

    // ── Final Model Allocation ──────────────────────────────────────────────
    ke_model_data *model = (ke_model_data *)ke_alloc(sizeof(ke_model_data), alignof(ke_model_data));
    if (!model)
    {
        KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "model allocation failed");
        return nullptr;
    }

    model->mesh_count = mesh_count;
    model->material_count = mat_count;
    model->texture_count = tex_count;

    model->meshes    = (ke_mesh_data *)   ke_alloc(sizeof(ke_mesh_data)    * mesh_count, alignof(ke_mesh_data));
    model->materials = (ke_material_data *)ke_alloc(sizeof(ke_material_data) * mat_count, alignof(ke_material_data));
    model->textures  = (ke_texture_data *) ke_alloc(sizeof(ke_texture_data)  * tex_count, alignof(ke_texture_data));

    if (mesh_count) memcpy(model->meshes, meshes.data(), sizeof(ke_mesh_data) * mesh_count);
    if (mat_count) memcpy(model->materials, mats.data(), sizeof(ke_material_data) * mat_count);
    if (tex_count) memcpy(model->textures, texs.data(), sizeof(ke_texture_data) * tex_count);

    log_info(logger_, "Model loaded successfully");
    return model;
}

ke_task *AssimpLoader::LoadModelAsync(ke_scheduler *scheduler,
                                       const char *path,
                                       ke_load_model_complete_func on_complete,
                                       void *user_data)
{
    if (!scheduler || !path || !on_complete) return nullptr;

    struct AsyncCtx
    {
        AssimpLoader               *self;
        char                       *path;      // heap-allocated copy
        ke_load_model_complete_func on_complete;
        void                       *user_data;
    };

    auto *ctx = static_cast<AsyncCtx *>(
        ke_alloc(sizeof(AsyncCtx), alignof(AsyncCtx)));
    if (!ctx) {
        on_complete(false, nullptr, user_data);
        return nullptr;
    }

    std::string path_copy(path);
    char *path_buf = static_cast<char *>(ke_alloc(path_copy.size() + 1, 1));
    if (!path_buf) {
        ke_free(ctx);
        on_complete(false, nullptr, user_data);
        return nullptr;
    }
    memcpy(path_buf, path_copy.c_str(), path_copy.size() + 1);

    ctx->self        = this;
    ctx->path        = path_buf;
    ctx->on_complete = on_complete;
    ctx->user_data   = user_data;

    return scheduler->dispatch(scheduler,
        [](void *data) {
            auto *c = static_cast<AsyncCtx *>(data);
            ke_model_data *model = c->self->LoadModel(c->path);
            static const ke_error_type s_load_fail_type = { "ke.asset.assimp.load_failed", &KE_ERROR_IO };
            static const ke_error s_load_fail = { &s_load_fail_type, "model load failed", nullptr, 0, nullptr };
            c->on_complete(model != nullptr ? nullptr : &s_load_fail, model, c->user_data);
            ke_free(c->path);
            ke_free(c);
        },
        ctx);
}

void AssimpLoader::FreeModel(ke_model_data *data)
{
    if (!data) return;
    for (uint32_t i = 0; i < data->mesh_count; i++) {
        ke_free(data->meshes[i].vertices);
        ke_free(data->meshes[i].indices);
    }
    ke_free(data->meshes);
    ke_free(data->materials);
    for (uint32_t i = 0; i < data->texture_count; i++)
        ke_free(data->textures[i].pixels);
    ke_free(data->textures);
    ke_free(data);
}

} // namespace kernel_engine::asset::assimp

extern "C" KE_ASSET_ASSIMP_API ke_asset_loader_handle
ke_asset_loader_assimp_create(const ke_asset_loader_assimp_params *params,
                               ke_error **out_error)
{
    if (!params)
    {
        KE_ERROR_SET(out_error, &KE_ERROR_INVALID_ARGUMENT, "invalid argument");
        return {nullptr, nullptr};
    }
    void *mem = ke_alloc(sizeof(kernel_engine::asset::assimp::AssimpLoader), alignof(kernel_engine::asset::assimp::AssimpLoader));
    if (!mem)
    {
        KE_ERROR_SET(out_error, &KE_ERROR_OUT_OF_MEMORY, "loader allocation failed");
        return {nullptr, nullptr};
    }
    auto *loader = new (mem) kernel_engine::asset::assimp::AssimpLoader(params);
    return {loader->ToApi(), &kernel_engine::asset::assimp::AssimpLoader::DestroyApi};
}
