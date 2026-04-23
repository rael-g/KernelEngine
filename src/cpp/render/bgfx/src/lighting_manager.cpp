#include "lighting_manager.hpp"
#include "texture_manager.hpp"
#include "render_context.hpp"
#include "gpu_device.hpp"
#include <bgfx/bgfx.h>
#include <vector>
#include <cstring>
#include <cmath>
#include <algorithm>

namespace kernel_engine::render::bgfx
{

ke_result LightingManager::SetDirectionalLight(const ke_directional_light *light)
{
    if (!light) return KE_ERROR_INVALID_ARGUMENT;
    light_dir[0] = light->dir_x; light_dir[1] = light->dir_y; light_dir[2] = light->dir_z; light_dir[3] = 0.f;
    light_color[0] = light->r * light->intensity; light_color[1] = light->g * light->intensity; light_color[2] = light->b * light->intensity; light_color[3] = 0.f;
    return KE_OK;
}

ke_result LightingManager::SetAmbientLight(float r, float g, float b)
{
    ambient_color[0] = r; ambient_color[1] = g; ambient_color[2] = b; ambient_color[3] = 0.f;
    return KE_OK;
}

ke_result LightingManager::SetPointLights(RenderContext& ctx, uint16_t buffer_handle, const ke_point_light *lights, uint32_t count)
{
    if (!lights && count > 0) return KE_ERROR_INVALID_ARGUMENT;
    if (!ctx.gpu) return KE_ERROR_RENDER;
    point_lights_.assign(lights, lights + count);

    struct GpuPointLight { float pos_r[4]; float color[4]; };
    std::vector<GpuPointLight> gpuLights(count);
    for (uint32_t i = 0; i < count; ++i)
    {
        gpuLights[i].pos_r[0] = lights[i].pos_x;
        gpuLights[i].pos_r[1] = lights[i].pos_y;
        gpuLights[i].pos_r[2] = lights[i].pos_z;
        gpuLights[i].pos_r[3] = lights[i].radius;
        gpuLights[i].color[0] = lights[i].r * lights[i].intensity;
        gpuLights[i].color[1] = lights[i].g * lights[i].intensity;
        gpuLights[i].color[2] = lights[i].b * lights[i].intensity;
        gpuLights[i].color[3] = 0.f;
    }

    if (count > 0 && ::bgfx::isValid(::bgfx::DynamicIndexBufferHandle{buffer_handle}))
    {
        ctx.gpu->UpdateDynamicIndexBuffer(::bgfx::DynamicIndexBufferHandle{buffer_handle}, 0,
                       ::bgfx::copy(gpuLights.data(), (uint32_t)(count * sizeof(GpuPointLight))));
    }
    return KE_OK;
}

ke_result LightingManager::SetSpotLights(RenderContext& ctx, uint16_t buffer_handle, const ke_spot_light *lights, uint32_t count)
{
    if (!lights && count > 0) return KE_ERROR_INVALID_ARGUMENT;
    if (!ctx.gpu) return KE_ERROR_RENDER;
    spot_lights_.assign(lights, lights + count);

    struct GpuSpotLight { float pos_r[4]; float dir_cosI[4]; float color_cosO[4]; };
    std::vector<GpuSpotLight> gpuLights(count);
    for (uint32_t i = 0; i < count; ++i)
    {
        gpuLights[i].pos_r[0] = lights[i].pos_x;
        gpuLights[i].pos_r[1] = lights[i].pos_y;
        gpuLights[i].pos_r[2] = lights[i].pos_z;
        gpuLights[i].pos_r[3] = lights[i].range;
        gpuLights[i].dir_cosI[0] = lights[i].dir_x;
        gpuLights[i].dir_cosI[1] = lights[i].dir_y;
        gpuLights[i].dir_cosI[2] = lights[i].dir_z;
        gpuLights[i].dir_cosI[3] = cosf(lights[i].inner_angle);
        gpuLights[i].color_cosO[0] = lights[i].r * lights[i].intensity;
        gpuLights[i].color_cosO[1] = lights[i].g * lights[i].intensity;
        gpuLights[i].color_cosO[2] = lights[i].b * lights[i].intensity;
        gpuLights[i].color_cosO[3] = cosf(lights[i].outer_angle);
    }

    if (count > 0 && ::bgfx::isValid(::bgfx::DynamicIndexBufferHandle{buffer_handle}))
    {
        ctx.gpu->UpdateDynamicIndexBuffer(::bgfx::DynamicIndexBufferHandle{buffer_handle}, 0,
                       ::bgfx::copy(gpuLights.data(), (uint32_t)(count * sizeof(GpuSpotLight))));
    }
    return KE_OK;
}

ke_result LightingManager::CreateMaterial(RenderContext& ctx, const TextureManager& textures, const ke_material *mat, ke_material_handle *out_handle)
{
    if (!mat || !out_handle) return KE_ERROR_INVALID_ARGUMENT;
    uint32_t tex  = mat->albedo;
    uint32_t nmap = mat->normal_map;
    materials_.push_back({mat->r, mat->g, mat->b, mat->a, tex, mat->metallic, mat->roughness, nmap, true});
    *out_handle = (ke_material_handle)(materials_.size() - 1);
    return KE_OK;
}

ke_result LightingManager::DestroyMaterial(RenderContext& ctx, ke_material_handle handle)
{
    if (handle >= (ke_material_handle)materials_.size()) return KE_ERROR_INVALID_ARGUMENT;
    materials_[handle].valid = false;
    return KE_OK;
}

void LightingManager::Shutdown()
{
    // GPU device handles cleanup
    materials_.clear();
}

const MaterialEntry& LightingManager::GetMaterial(ke_material_handle handle) const
{
    static MaterialEntry s_invalid;
    if (handle < materials_.size()) return materials_[handle];
    return s_invalid;
}

} // namespace kernel_engine::render::bgfx
