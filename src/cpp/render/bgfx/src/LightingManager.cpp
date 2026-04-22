#include "LightingManager.hpp"
#include "BgfxRenderer.hpp"
#include "bgfx_interface.hh"
#include <vector>
#include <cstring>
#include <cmath>
#include <algorithm>

namespace kernel_engine::render::bgfx
{

ke_result LightingManager::SetDirectionalLight(const ke_directional_light *light)
{
    if (!light) return KE_ERROR_INVALID_ARGUMENT;
    light_dir_[0] = light->dir_x; light_dir_[1] = light->dir_y; light_dir_[2] = light->dir_z; light_dir_[3] = 0.f;
    light_color_[0] = light->r * light->intensity; light_color_[1] = light->g * light->intensity; light_color_[2] = light->b * light->intensity; light_color_[3] = 0.f;
    return KE_OK;
}

ke_result LightingManager::SetAmbientLight(float r, float g, float b)
{
    ambient_color_[0] = r; ambient_color_[1] = g; ambient_color_[2] = b; ambient_color_[3] = 0.f;
    return KE_OK;
}

ke_result LightingManager::SetPointLights(const ke_point_light *lights, uint32_t count)
{
    if (!lights && count > 0) return KE_ERROR_INVALID_ARGUMENT;
    auto* renderer = static_cast<BgfxRenderer*>(this);
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

    if (count > 0)
    {
        renderer->bgfx_->Update(::bgfx::DynamicIndexBufferHandle{renderer->b_point_lights_}, 0,
                       renderer->bgfx_->Copy(gpuLights.data(), (uint32_t)(count * sizeof(GpuPointLight))));
    }
    return KE_OK;
}

ke_result LightingManager::SetSpotLights(const ke_spot_light *lights, uint32_t count)
{
    if (!lights && count > 0) return KE_ERROR_INVALID_ARGUMENT;
    auto* renderer = static_cast<BgfxRenderer*>(this);
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

    if (count > 0)
    {
        renderer->bgfx_->Update(::bgfx::DynamicIndexBufferHandle{renderer->b_spot_lights_}, 0,
                       renderer->bgfx_->Copy(gpuLights.data(), (uint32_t)(count * sizeof(GpuSpotLight))));
    }
    return KE_OK;
}

ke_result LightingManager::CreateMaterial(const ke_material *mat, ke_material_handle *out_handle)
{
    if (!mat || !out_handle) return KE_ERROR_INVALID_ARGUMENT;
    auto* renderer = static_cast<BgfxRenderer*>(this);
    uint32_t tex  = (mat->albedo     < (ke_texture_handle)renderer->textures_.size()) ? mat->albedo     : 0;
    uint32_t nmap = (mat->normal_map < (ke_texture_handle)renderer->textures_.size()) ? mat->normal_map : 0;
    materials_.push_back({mat->r, mat->g, mat->b, mat->a, tex, mat->metallic, mat->roughness, nmap, true});
    *out_handle = (ke_material_handle)(materials_.size() - 1);
    return KE_OK;
}

ke_result LightingManager::DestroyMaterial(ke_material_handle handle)
{
    if (handle >= (ke_material_handle)materials_.size()) return KE_ERROR_INVALID_ARGUMENT;
    materials_[handle].valid = false;
    return KE_OK;
}

} // namespace kernel_engine::render::bgfx
