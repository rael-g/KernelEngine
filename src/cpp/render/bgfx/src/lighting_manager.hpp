#pragma once

#include <kernel_engine/kernel/common/error.h>
#include <kernel_engine/kernel/render/light.h>
#include <kernel_engine/kernel/render/material.h>
#include <kernel_engine/render/bgfx/bgfx_render.h>
#include "internal_types.hpp"
#include <vector>

namespace kernel_engine::render::bgfx
{

struct RenderContext;
class TextureManager;

struct MaterialEntry
{
    float r = 1.f, g = 1.f, b = 1.f, a = 1.f;
    uint32_t texture_handle     = 0;            // index into textures_
    float metallic              = 0.f;
    float roughness             = 0.5f;
    uint32_t normal_map_handle  = 0;            // 0 = disabled
    bool valid = false;
};

/**
 * @brief Manages light sources and PBR materials.
 */
class KE_RENDER_API LightingManager
{
public:
    ke_result SetDirectionalLight(const ke_directional_light *light);
    ke_result SetAmbientLight(float r, float g, float b);
    ke_result SetPointLights(RenderContext& ctx, uint16_t buffer_handle, const ke_point_light *lights, uint32_t count);
    ke_result SetSpotLights(RenderContext& ctx, uint16_t buffer_handle, const ke_spot_light *lights, uint32_t count);
    
    ke_result CreateMaterial(RenderContext& ctx, const TextureManager& textures, const ke_material *mat, ke_material_handle *out_handle);
    ke_result DestroyMaterial(RenderContext& ctx, ke_material_handle handle);

    void Shutdown();

    const MaterialEntry& GetMaterial(ke_material_handle handle) const;
    size_t GetPointLightCount() const { return point_lights_.size(); }
    size_t GetSpotLightCount() const { return spot_lights_.size(); }

    uint16_t light_dir_uniform      = kInvalidHandle;
    uint16_t light_color_uniform    = kInvalidHandle;
    uint16_t ambient_color_uniform  = kInvalidHandle;
    uint16_t pbr_params_uniform     = kInvalidHandle;
    uint16_t camera_pos_uniform     = kInvalidHandle;
    uint16_t ibl_params_uniform     = kInvalidHandle;
    uint16_t env_map_uniform        = kInvalidHandle;
    uint16_t normal_map_uniform     = kInvalidHandle;
    uint16_t normal_params_uniform  = kInvalidHandle;
    uint16_t light_counts_uniform   = kInvalidHandle;
    uint16_t point_lights_uniform   = kInvalidHandle;
    uint16_t spot_lights_uniform    = kInvalidHandle;
    uint16_t color_uniform          = kInvalidHandle;

    float light_dir[4]     = {0.f,  1.f, 0.f, 0.f};
    float light_color[4]   = {0.f,  0.f, 0.f, 0.f};
    float ambient_color[4] = {0.1f, 0.1f, 0.1f, 0.f};

private:
    std::vector<MaterialEntry> materials_;
    std::vector<ke_point_light> point_lights_;
    std::vector<ke_spot_light>  spot_lights_;
};

} // namespace kernel_engine::render::bgfx
