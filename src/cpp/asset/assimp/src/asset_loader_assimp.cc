#define STB_IMAGE_IMPLEMENTATION
#include <stb_image.h>

#include <kernel_engine/asset/assimp/ke_asset_loader_assimp.hh>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/logger/logger.h>
#include <assimp/Importer.hpp>
#include <assimp/scene.h>
#include <assimp/postprocess.h>
#include <cstring>
#include <cmath>
#include <string>
#include <unordered_map>
#include <vector>
#include <new>

namespace kernel_engine::asset::assimp
{

// ─────────────────────────────────────────────────────────────────────────────
// Internal helpers
// ─────────────────────────────────────────────────────────────────────────────

static void *ke_alloc(ke_allocator *a, size_t n)
{
    return a->alloc(a, n, alignof(void *));
}

static void ke_free(ke_allocator *a, void *p)
{
    if (p) a->free(a, p);
}

static void log_info(ke_logger *logger, const char *msg)
{
    if (!logger) return;
    ke_log_event ev = {KE_LOG_LEVEL_INFO, "asset_loader", msg};
    logger->log(logger, &ev);
}

static void log_warn(ke_logger *logger, const char *msg)
{
    if (!logger) return;
    ke_log_event ev = {KE_LOG_LEVEL_WARNING, "asset_loader", msg};
    logger->log(logger, &ev);
}

static void log_error(ke_logger *logger, const char *msg)
{
    if (!logger) return;
    ke_log_event ev = {KE_LOG_LEVEL_ERROR, "asset_loader", msg};
    logger->log(logger, &ev);
}

// ─────────────────────────────────────────────────────────────────────────────
// AssimpLoader class
// ─────────────────────────────────────────────────────────────────────────────

class AssimpLoader
{
  public:
    explicit AssimpLoader(const ke_asset_loader_assimp_params *params)
        : allocator_(params->allocator), logger_(params->logger)
    {
        api_.handle     = this;
        api_.destroy    = [](ke_asset_loader *self) {
            auto *l = static_cast<AssimpLoader *>(self->handle);
            auto *a = l->allocator_;
            l->~AssimpLoader();
            a->free(a, l);
        };
        api_.load_model = [](ke_asset_loader *self, const char *path, ke_model_data **out) {
            return static_cast<AssimpLoader *>(self->handle)->LoadModel(path, out);
        };
        api_.free_model = [](ke_asset_loader *self, ke_model_data *data) {
            static_cast<AssimpLoader *>(self->handle)->FreeModel(data);
        };
    }

    ~AssimpLoader() = default;

    ke_asset_loader *ToApi() { return &api_; }

    ke_result LoadModel(const char *path, ke_model_data **out)
    {
        if (!path || !out) return KE_ERROR_INVALID_ARGUMENT;

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
            log_error(logger_, importer.GetErrorString());
            return KE_ERROR_IO;
        }

        // ── Directory of the model file (for resolving texture paths) ─────────
        std::string dir(path);
        auto slash = dir.find_last_of("/\\");
        if (slash != std::string::npos) dir = dir.substr(0, slash + 1);
        else dir = "";

        // ── Collect unique texture paths ──────────────────────────────────────
        // Maps texture path/key → index in textures vector
        std::unordered_map<std::string, uint32_t> tex_index_map;
        std::vector<const aiTexture *> embedded_refs; // parallel to tex_index vector
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

            if (key[0] == '*')
            {
                // Embedded texture reference: "*N"
                uint32_t embedded_idx = (uint32_t)std::stoul(key.substr(1));
                embedded_refs.push_back(embedded_idx < scene->mNumTextures
                    ? scene->mTextures[embedded_idx] : nullptr);
                external_paths.push_back("");
                is_embedded.push_back(true);
            }
            else
            {
                embedded_refs.push_back(nullptr);
                external_paths.push_back(dir + key);
                is_embedded.push_back(false);
            }
            return (int32_t)idx;
        };

        // ── Build material list ───────────────────────────────────────────────
        uint32_t mat_count = scene->mNumMaterials;
        std::vector<ke_material_data> mats(mat_count);
        std::vector<int32_t> albedo_tex(mat_count, -1);
        std::vector<int32_t> normal_tex(mat_count, -1);

        for (uint32_t mi = 0; mi < mat_count; ++mi)
        {
            const aiMaterial *am = scene->mMaterials[mi];
            ke_material_data &md = mats[mi];
            memset(&md, 0, sizeof(md));

            // Name
            aiString name;
            if (am->Get(AI_MATKEY_NAME, name) == AI_SUCCESS)
                strncpy(md.name, name.C_Str(), sizeof(md.name) - 1);

            // Base color — try PBR first, fall back to diffuse
            aiColor4D color(1.f, 1.f, 1.f, 1.f);
            if (am->Get(AI_MATKEY_BASE_COLOR, color) != AI_SUCCESS)
                am->Get(AI_MATKEY_COLOR_DIFFUSE, color);
            md.base_color_r = color.r; md.base_color_g = color.g;
            md.base_color_b = color.b; md.base_color_a = color.a;

            float metallic = 0.f, roughness = 0.5f;
            am->Get(AI_MATKEY_METALLIC_FACTOR, metallic);
            am->Get(AI_MATKEY_ROUGHNESS_FACTOR, roughness);
            md.metallic  = metallic;
            md.roughness = roughness;

            // Textures — PBR base color or diffuse
            int32_t alb = register_texture(am, aiTextureType_BASE_COLOR);
            if (alb < 0) alb = register_texture(am, aiTextureType_DIFFUSE);
            albedo_tex[mi] = alb;

            // Normal map
            int32_t nrm = register_texture(am, aiTextureType_NORMALS);
            if (nrm < 0) nrm = register_texture(am, aiTextureType_HEIGHT);
            normal_tex[mi] = nrm;
        }

        // ── Decode textures ───────────────────────────────────────────────────
        uint32_t tex_count = (uint32_t)tex_index_map.size();
        std::vector<ke_texture_data> texs(tex_count);
        std::vector<uint8_t *> stbi_ptrs(tex_count, nullptr); // to free with stbi_image_free

        for (uint32_t ti = 0; ti < tex_count; ++ti)
        {
            ke_texture_data &td = texs[ti];
            memset(&td, 0, sizeof(td));
            int w = 0, h = 0, ch = 0;
            uint8_t *raw = nullptr;

            if (is_embedded[ti] && embedded_refs[ti])
            {
                const aiTexture *et = embedded_refs[ti];
                if (et->mHeight == 0)
                {
                    // Compressed in-memory (PNG/JPEG inside GLB)
                    raw = stbi_load_from_memory(
                        reinterpret_cast<const stbi_uc *>(et->pcData),
                        (int)et->mWidth, &w, &h, &ch, 4);
                }
                else
                {
                    // Already raw ARGB8888 — convert to RGBA8
                    w = (int)et->mWidth; h = (int)et->mHeight;
                    raw = (uint8_t *)malloc((size_t)w * h * 4);
                    if (raw)
                    {
                        const aiTexel *src = et->pcData;
                        for (int px = 0; px < w * h; ++px)
                        {
                            raw[px * 4 + 0] = src[px].r;
                            raw[px * 4 + 1] = src[px].g;
                            raw[px * 4 + 2] = src[px].b;
                            raw[px * 4 + 3] = src[px].a;
                        }
                    }
                }
            }
            else if (!external_paths[ti].empty())
            {
                raw = stbi_load(external_paths[ti].c_str(), &w, &h, &ch, 4);
                strncpy(td.path, external_paths[ti].c_str(), sizeof(td.path) - 1);
            }

            if (!raw)
            {
                // Fallback: 1x1 white pixel
                log_warn(logger_, "Failed to load texture; using white fallback");
                raw = (uint8_t *)malloc(4);
                if (raw) { raw[0] = raw[1] = raw[2] = raw[3] = 0xFF; }
                w = h = 1;
            }

            // Copy into allocator-owned memory
            size_t byte_count = (size_t)w * h * 4;
            td.pixels = (uint8_t *)ke_alloc(allocator_, byte_count);
            if (td.pixels) memcpy(td.pixels, raw, byte_count);
            td.width  = (uint32_t)w;
            td.height = (uint32_t)h;
            stbi_ptrs[ti] = raw; // free after copy
        }

        // Free stbi pixel buffers
        for (uint32_t ti = 0; ti < tex_count; ++ti)
            if (stbi_ptrs[ti]) free(stbi_ptrs[ti]);

        // Patch texture indices into material data
        for (uint32_t mi = 0; mi < mat_count; ++mi)
        {
            mats[mi].albedo_texture_index     = albedo_tex[mi];
            mats[mi].normal_map_texture_index = normal_tex[mi];
        }

        // ── Build mesh list ───────────────────────────────────────────────────
        uint32_t mesh_count = scene->mNumMeshes;
        std::vector<ke_mesh_data> meshes(mesh_count);
        std::vector<ke_vertex *>  vert_bufs(mesh_count, nullptr);
        std::vector<uint16_t *>   idx_bufs(mesh_count, nullptr);

        for (uint32_t si = 0; si < mesh_count; ++si)
        {
            const aiMesh *am = scene->mMeshes[si];
            ke_mesh_data &md = meshes[si];
            memset(&md, 0, sizeof(md));

            strncpy(md.name, am->mName.C_Str(), sizeof(md.name) - 1);
            md.material_index = (am->mMaterialIndex < mat_count)
                                ? (int32_t)am->mMaterialIndex : -1;
            md.vertex_count = am->mNumVertices;
            md.index_count  = am->mNumFaces * 3;

            // Allocate vertex buffer
            md.vertices = (ke_vertex *)ke_alloc(allocator_,
                sizeof(ke_vertex) * am->mNumVertices);
            vert_bufs[si] = md.vertices;
            if (!md.vertices) return KE_ERROR_OUT_OF_MEMORY;

            // Allocate index buffer
            md.indices = (uint16_t *)ke_alloc(allocator_,
                sizeof(uint16_t) * md.index_count);
            idx_bufs[si] = md.indices;
            if (!md.indices) return KE_ERROR_OUT_OF_MEMORY;

            // Fill vertices
            for (uint32_t vi = 0; vi < am->mNumVertices; ++vi)
            {
                ke_vertex &v = md.vertices[vi];
                memset(&v, 0, sizeof(v));
                v.x = am->mVertices[vi].x;
                v.y = am->mVertices[vi].y;
                v.z = am->mVertices[vi].z;

                if (am->HasNormals())
                {
                    v.nx = am->mNormals[vi].x;
                    v.ny = am->mNormals[vi].y;
                    v.nz = am->mNormals[vi].z;
                }
                else { v.nz = 1.f; }

                if (am->HasTextureCoords(0))
                {
                    v.u = am->mTextureCoords[0][vi].x;
                    v.v = am->mTextureCoords[0][vi].y;
                }

                if (am->HasTangentsAndBitangents())
                {
                    const aiVector3D &T = am->mTangents[vi];
                    const aiVector3D &B = am->mBitangents[vi];
                    const aiVector3D &N = am->mNormals[vi];
                    v.tx = T.x; v.ty = T.y; v.tz = T.z;

                    // Bitangent sign: sign(dot(cross(N, T), B))
                    float cx = N.y * T.z - N.z * T.y;
                    float cy = N.z * T.x - N.x * T.z;
                    float cz = N.x * T.y - N.y * T.x;
                    v.tw = (cx * B.x + cy * B.y + cz * B.z >= 0.f) ? 1.f : -1.f;
                }
                else
                {
                    v.tx = 1.f; v.ty = 0.f; v.tz = 0.f; v.tw = 1.f;
                }
            }

            // Fill indices
            uint32_t idx_cursor = 0;
            for (uint32_t fi = 0; fi < am->mNumFaces; ++fi)
            {
                const aiFace &face = am->mFaces[fi];
                for (uint32_t j = 0; j < 3 && j < face.mNumIndices; ++j)
                    md.indices[idx_cursor++] = (uint16_t)face.mIndices[j];
            }
            md.index_count = idx_cursor;
        }

        // ── Allocate and fill ke_model_data ───────────────────────────────────
        ke_model_data *model = (ke_model_data *)ke_alloc(allocator_, sizeof(ke_model_data));
        if (!model) return KE_ERROR_OUT_OF_MEMORY;

        model->mesh_count     = mesh_count;
        model->material_count = mat_count;
        model->texture_count  = tex_count;

        model->meshes = (ke_mesh_data *)ke_alloc(allocator_,
            sizeof(ke_mesh_data) * mesh_count);
        model->materials = (ke_material_data *)ke_alloc(allocator_,
            sizeof(ke_material_data) * mat_count);
        model->textures = (ke_texture_data *)ke_alloc(allocator_,
            sizeof(ke_texture_data) * tex_count);

        if (mesh_count && !model->meshes)     return KE_ERROR_OUT_OF_MEMORY;
        if (mat_count  && !model->materials)  return KE_ERROR_OUT_OF_MEMORY;
        if (tex_count  && !model->textures)   return KE_ERROR_OUT_OF_MEMORY;

        memcpy(model->meshes,    meshes.data(),  sizeof(ke_mesh_data)     * mesh_count);
        memcpy(model->materials, mats.data(),    sizeof(ke_material_data) * mat_count);
        memcpy(model->textures,  texs.data(),    sizeof(ke_texture_data)  * tex_count);

        *out = model;
        log_info(logger_, "Model loaded successfully");
        return KE_OK;
    }

    void FreeModel(ke_model_data *data)
    {
        if (!data) return;

        for (uint32_t i = 0; i < data->mesh_count; ++i)
        {
            ke_free(allocator_, data->meshes[i].vertices);
            ke_free(allocator_, data->meshes[i].indices);
        }
        ke_free(allocator_, data->meshes);

        ke_free(allocator_, data->materials);

        for (uint32_t i = 0; i < data->texture_count; ++i)
            ke_free(allocator_, data->textures[i].pixels);
        ke_free(allocator_, data->textures);

        ke_free(allocator_, data);
    }

  private:
    ke_allocator    *allocator_;
    ke_logger       *logger_;
    ke_asset_loader  api_{};
};

} // namespace kernel_engine::asset::assimp

// ─────────────────────────────────────────────────────────────────────────────
// C factory function
// ─────────────────────────────────────────────────────────────────────────────

extern "C" KE_ASSET_ASSIMP_API ke_result
ke_asset_loader_assimp_create(const ke_asset_loader_assimp_params *params,
                               ke_asset_loader **out)
{
    if (!params || !params->allocator || !out) return KE_ERROR_INVALID_ARGUMENT;

    void *mem = params->allocator->alloc(params->allocator,
        sizeof(kernel_engine::asset::assimp::AssimpLoader),
        alignof(kernel_engine::asset::assimp::AssimpLoader));
    if (!mem) return KE_ERROR_OUT_OF_MEMORY;

    auto *loader = new (mem) kernel_engine::asset::assimp::AssimpLoader(params);
    *out = loader->ToApi();
    return KE_OK;
}
