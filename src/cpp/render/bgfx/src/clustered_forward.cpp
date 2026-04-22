#include "clustered_forward.hpp"
#include "bgfx_renderer.hpp"
#include "bgfx_interface.hh"
#include <fstream>
#include <vector>
#include <cmath>
#include <algorithm>

namespace kernel_engine::render::bgfx
{

ke_result ClusteredForward::SetupClustered()
{
    auto* renderer = static_cast<BgfxRenderer*>(this);
    
    auto load_shader = [&](const char *name) -> ::bgfx::ShaderHandle {
        std::string path = renderer->shader_path_ + "/" + name + ".bin";
        std::ifstream file(path, std::ios::binary | std::ios::ate);
        if (!file.is_open()) return ::bgfx::ShaderHandle{::bgfx::kInvalidHandle};
        auto size = (uint32_t)file.tellg();
        file.seekg(0);
        const ::bgfx::Memory *mem = renderer->bgfx_->Alloc(size);
        file.read(reinterpret_cast<char *>(mem->data), size);
        return renderer->bgfx_->CreateShader(mem);
    };

    ::bgfx::ShaderHandle vs_d = load_shader("vs_depth");
    ::bgfx::ShaderHandle fs_d = load_shader("fs_depth");
    if (::bgfx::isValid(vs_d) && ::bgfx::isValid(fs_d))
        renderer->depth_program_ = renderer->bgfx_->CreateProgram(vs_d, fs_d, true).idx;

    ::bgfx::ShaderHandle cs_c = load_shader("cs_light_cull");
    if (::bgfx::isValid(cs_c))
        renderer->cull_program_ = renderer->bgfx_->CreateProgram(cs_c, true).idx;

    cluster_params_u_  = renderer->bgfx_->CreateUniform("u_clusterParams",  ::bgfx::UniformType::Vec4).idx;
    cluster_params2_u_ = renderer->bgfx_->CreateUniform("u_clusterParams2", ::bgfx::UniformType::Vec4).idx;
    compute_view_u_    = renderer->bgfx_->CreateUniform("u_computeView",    ::bgfx::UniformType::Mat4).idx;

    RebuildClusterBuffers();
    return KE_OK;
}

void ClusteredForward::RebuildClusterBuffers()
{
    auto* renderer = static_cast<BgfxRenderer*>(this);
    auto destroy_buffer = [&](uint16_t &h) {
        if (::bgfx::isValid(::bgfx::DynamicIndexBufferHandle{h})) renderer->bgfx_->Destroy(::bgfx::DynamicIndexBufferHandle{h});
        h = kInvalidHandle;
    };

    destroy_buffer(b_cluster_bounds_);
    destroy_buffer(b_point_lights_);
    destroy_buffer(b_spot_lights_);
    destroy_buffer(b_p_light_indices_);
    destroy_buffer(b_p_light_count_);
    destroy_buffer(b_s_light_indices_);
    destroy_buffer(b_s_light_count_);

    uint32_t numClusters = cluster_config_.grid_x * cluster_config_.grid_y * cluster_config_.grid_z;

    b_cluster_bounds_ = renderer->bgfx_->CreateDynamicIndexBuffer(numClusters * 32 / 2, BGFX_BUFFER_COMPUTE_READ).idx;
    b_point_lights_ = renderer->bgfx_->CreateDynamicIndexBuffer(cluster_config_.max_total_lights * 32 / 2, BGFX_BUFFER_COMPUTE_READ).idx;
    b_spot_lights_  = renderer->bgfx_->CreateDynamicIndexBuffer(cluster_config_.max_total_lights * 48 / 2, BGFX_BUFFER_COMPUTE_READ).idx;
    b_p_light_indices_ = renderer->bgfx_->CreateDynamicIndexBuffer(numClusters * cluster_config_.max_lights_per_cluster * 4 / 2, BGFX_BUFFER_COMPUTE_READ_WRITE).idx;
    b_s_light_indices_ = renderer->bgfx_->CreateDynamicIndexBuffer(numClusters * cluster_config_.max_lights_per_cluster * 4 / 2, BGFX_BUFFER_COMPUTE_READ_WRITE).idx;
    b_p_light_count_ = renderer->bgfx_->CreateDynamicIndexBuffer(numClusters * 4 / 2, BGFX_BUFFER_COMPUTE_READ_WRITE).idx;
    b_s_light_count_ = renderer->bgfx_->CreateDynamicIndexBuffer(numClusters * 4 / 2, BGFX_BUFFER_COMPUTE_READ_WRITE).idx;

    bounds_dirty_ = true;
}

void ClusteredForward::UpdateClusterBounds()
{
    if (!bounds_dirty_) return;
    auto* renderer = static_cast<BgfxRenderer*>(this);

    float nearZ = renderer->near_z_;
    float farZ  = renderer->far_z_;
    uint32_t numX = cluster_config_.grid_x;
    uint32_t numY = cluster_config_.grid_y;
    uint32_t numZ = cluster_config_.grid_z;

    struct AABB { float min[4]; float max[4]; };
    std::vector<AABB> bounds(numX * numY * numZ);

    float invProj00 = 1.0f / renderer->last_proj_[0];
    float invProj11 = 1.0f / renderer->last_proj_[5];

    for (uint32_t iz = 0; iz < numZ; ++iz)
    {
        float z0 = nearZ * powf(farZ / nearZ, (float)iz / numZ);
        float z1 = nearZ * powf(farZ / nearZ, (float)(iz + 1) / numZ);
        for (uint32_t iy = 0; iy < numY; ++iy)
        {
            float yNDC0 = (float)iy / numY * 2.0f - 1.0f;
            float yNDC1 = (float)(iy + 1) / numY * 2.0f - 1.0f;
            for (uint32_t ix = 0; ix < numX; ++ix)
            {
                float xNDC0 = (float)ix / numX * 2.0f - 1.0f;
                float xNDC1 = (float)(ix + 1) / numX * 2.0f - 1.0f;
                float vz0 = -z0;
                float vz1 = -z1;
                float x0z0 = xNDC0 * z0 * invProj00;
                float x1z0 = xNDC1 * z0 * invProj00;
                float y0z0 = yNDC0 * z0 * invProj11;
                float y1z0 = yNDC1 * z0 * invProj11;
                float x0z1 = xNDC0 * z1 * invProj00;
                float x1z1 = xNDC1 * z1 * invProj00;
                float y0z1 = yNDC0 * z1 * invProj11;
                float y1z1 = yNDC1 * z1 * invProj11;

                AABB &b = bounds[iz * numX * numY + iy * numX + ix];
                b.min[0] = std::min({x0z0, x1z0, x0z1, x1z1});
                b.min[1] = std::min({y0z0, y1z0, y0z1, y1z1});
                b.min[2] = vz1;
                b.min[3] = 0.0f;
                b.max[0] = std::max({x0z0, x1z0, x0z1, x1z1});
                b.max[1] = std::max({y0z0, y1z0, y0z1, y1z1});
                b.max[2] = vz0;
                b.max[3] = 0.0f;
            }
        }
    }

    renderer->bgfx_->Update(::bgfx::DynamicIndexBufferHandle{b_cluster_bounds_}, 0,
                   renderer->bgfx_->Copy(bounds.data(), (uint32_t)(bounds.size() * sizeof(AABB))));
    bounds_dirty_ = false;
}

void ClusteredForward::DispatchLightCull()
{
    auto* renderer = static_cast<BgfxRenderer*>(this);
    if (renderer->cull_program_ == kInvalidHandle) return;

    renderer->bgfx_->SetUniform(::bgfx::UniformHandle{compute_view_u_}, renderer->last_view_);

    float params[4] = {(float)cluster_config_.grid_x, (float)cluster_config_.grid_y,
                       (float)cluster_config_.grid_z, (float)cluster_config_.max_lights_per_cluster};
    renderer->bgfx_->SetUniform(::bgfx::UniformHandle{cluster_params_u_}, params);

    float params2[4] = {(float)renderer->point_lights_.size(), (float)renderer->spot_lights_.size(), 0.f, 0.f};
    renderer->bgfx_->SetUniform(::bgfx::UniformHandle{cluster_params2_u_}, params2);

    renderer->bgfx_->SetBuffer(0, ::bgfx::DynamicIndexBufferHandle{b_cluster_bounds_}, ::bgfx::Access::Read);
    renderer->bgfx_->SetBuffer(1, ::bgfx::DynamicIndexBufferHandle{b_point_lights_},   ::bgfx::Access::Read);
    renderer->bgfx_->SetBuffer(2, ::bgfx::DynamicIndexBufferHandle{b_spot_lights_},    ::bgfx::Access::Read);

    renderer->bgfx_->SetBuffer(3, ::bgfx::DynamicIndexBufferHandle{b_p_light_indices_}, ::bgfx::Access::ReadWrite);
    renderer->bgfx_->SetBuffer(4, ::bgfx::DynamicIndexBufferHandle{b_p_light_count_},   ::bgfx::Access::ReadWrite);
    renderer->bgfx_->SetBuffer(5, ::bgfx::DynamicIndexBufferHandle{b_s_light_indices_}, ::bgfx::Access::ReadWrite);
    renderer->bgfx_->SetBuffer(6, ::bgfx::DynamicIndexBufferHandle{b_s_light_count_},   ::bgfx::Access::ReadWrite);

    renderer->bgfx_->Dispatch(kLightCullView, ::bgfx::ProgramHandle{renderer->cull_program_},
                     (uint16_t)cluster_config_.grid_x, (uint16_t)cluster_config_.grid_y, (uint16_t)cluster_config_.grid_z);
}

ke_result ClusteredForward::SetClusterConfig(const ke_cluster_config *config)
{
    auto* renderer = static_cast<BgfxRenderer*>(this);
    if (!renderer->initialized_) return KE_ERROR_NOT_INITIALIZED;
    if (!config) return KE_ERROR_INVALID_ARGUMENT;
    if (config->grid_x == 0 || config->grid_y == 0 || config->grid_z == 0) return KE_ERROR_INVALID_ARGUMENT;
    cluster_config_ = *config;
    RebuildClusterBuffers();
    return KE_OK;
}

} // namespace kernel_engine::render::bgfx
