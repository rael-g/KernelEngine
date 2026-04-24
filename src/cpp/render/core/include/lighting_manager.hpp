#pragma once

#include <kernel_engine/kernel/render/render.h>
#include <kernel_engine/kernel/engine/frame_packet.h>
#include "internal_types.hpp"
#include "gpu_types.hpp"
#include <vector>

namespace kernel_engine::render::bgfx
{

struct RenderContext;
class TextureManager;

struct MaterialEntry
{
    float r, g, b, a;
    uint32_t texture_handle;
    float metallic;
    float roughness;
    uint32_t normal_map_handle;
    bool valid;
};

/**
 * @brief Manages light data and materials using the HAL.
 */
class KE_RENDER_API LightingManager
{
public:
    ke_result SetDirectionalLight(const ke_directional_light *light);
    ke_result SetAmbientLight(float r, float g, float b);
    
    // Immediate-mode: store for current frame (used by vtable path)
    ke_result StorePointLights(const ke_point_light *lights, uint32_t count);
    ke_result StoreSpotLights(const ke_spot_light *lights, uint32_t count);

    // Recording methods for multithreading
    ke_result RecordLights(struct ke_frame_packet& packet, const ke_point_light *lights, uint32_t count);
    ke_result RecordSpotLights(struct ke_frame_packet& packet, const ke_spot_light *lights, uint32_t count);
    
    ke_result CreateMaterial(RenderContext& ctx, const TextureManager& textures, const ke_material *mat, ke_material_handle *out_handle);
    ke_result DestroyMaterial(RenderContext& ctx, ke_material_handle handle);

    void Shutdown();

    const MaterialEntry& GetMaterial(ke_material_handle handle) const;
    uint32_t GetPointLightCount() const { return (uint32_t)point_lights_.size(); }
    uint32_t GetSpotLightCount() const { return (uint32_t)spot_lights_.size(); }

    GpuUniformHandle env_map_uniform        = kGpuInvalidHandle;
    GpuUniformHandle color_uniform          = kGpuInvalidHandle;
    GpuUniformHandle light_dir_uniform      = kGpuInvalidHandle;
    GpuUniformHandle light_color_uniform    = kGpuInvalidHandle;
    GpuUniformHandle ambient_color_uniform  = kGpuInvalidHandle;
    GpuUniformHandle pbr_params_uniform     = kGpuInvalidHandle;
    GpuUniformHandle camera_pos_uniform     = kGpuInvalidHandle;
    GpuUniformHandle ibl_params_uniform     = kGpuInvalidHandle;
    GpuUniformHandle normal_map_uniform     = kGpuInvalidHandle;
    GpuUniformHandle normal_params_uniform  = kGpuInvalidHandle;
    GpuUniformHandle light_counts_uniform   = kGpuInvalidHandle;
    GpuUniformHandle point_lights_uniform   = kGpuInvalidHandle;
    GpuUniformHandle spot_lights_uniform    = kGpuInvalidHandle;

    float light_dir[4]     = {0.f, -1.f, 0.f, 0.f};
    float light_color[4]   = {1.f, 1.f, 1.f, 1.f};
    float ambient_color[4] = {0.1f, 0.1f, 0.1f, 0.f};

private:
    std::vector<MaterialEntry> materials_;
    std::vector<ke_point_light> point_lights_;
    std::vector<ke_spot_light>  spot_lights_;
};

} // namespace kernel_engine::render::bgfx
