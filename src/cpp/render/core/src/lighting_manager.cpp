#include "lighting_manager.hpp"
#include <render_logging.hpp>
#include "texture_manager.hpp"
#include "render_context.hpp"
#include "gpu_device.hpp"
#include <vector>
#include <cstring>
#include <cmath>
#include <algorithm>


namespace kernel_engine::render::core
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

ke_result LightingManager::StorePointLights(const ke_point_light *lights, uint32_t count)
{
    if (!lights && count > 0) return KE_ERROR_INVALID_ARGUMENT;
    point_lights_.assign(lights, lights + count);
    return KE_OK;
}

ke_result LightingManager::StoreSpotLights(const ke_spot_light *lights, uint32_t count)
{
    if (!lights && count > 0) return KE_ERROR_INVALID_ARGUMENT;
    spot_lights_.assign(lights, lights + count);
    return KE_OK;
}

void LightingManager::UploadLights(RenderContext& ctx)
{
    if (!ctx.gpu) return;

    uint32_t pc = (uint32_t)point_lights_.size();
    if (pc > kMaxPointLights) pc = kMaxPointLights;
    uint32_t sc = (uint32_t)spot_lights_.size();
    if (sc > kMaxSpotLights) sc = kMaxSpotLights;

    // Point lights: 2 vec4 each — [pos.xyz, radius] | [color.rgb, intensity].
    if (pc > 0 && point_lights_uniform != kGpuInvalidHandle)
    {
        float buf[kMaxPointLights * 8];
        for (uint32_t i = 0; i < pc; ++i)
        {
            const ke_point_light& l = point_lights_[i];
            float* v = &buf[i * 8];
            v[0] = l.pos_x; v[1] = l.pos_y; v[2] = l.pos_z; v[3] = l.radius;
            v[4] = l.r;     v[5] = l.g;     v[6] = l.b;     v[7] = l.intensity;
        }
        ctx.gpu->SetUniform(point_lights_uniform, buf, (uint16_t)(pc * 2));
    }

    // Spot lights: 4 vec4 each — [pos.xyz, range] | [dir.xyz, cos(inner)] | [color.rgb, intensity] | [cos(outer),0,0,0].
    if (sc > 0 && spot_lights_uniform != kGpuInvalidHandle)
    {
        float buf[kMaxSpotLights * 16];
        for (uint32_t i = 0; i < sc; ++i)
        {
            const ke_spot_light& l = spot_lights_[i];
            float* v = &buf[i * 16];
            v[0]  = l.pos_x; v[1]  = l.pos_y; v[2]  = l.pos_z; v[3]  = l.range;
            v[4]  = l.dir_x; v[5]  = l.dir_y; v[6]  = l.dir_z; v[7]  = std::cos(l.inner_angle);
            v[8]  = l.r;     v[9]  = l.g;     v[10] = l.b;     v[11] = l.intensity;
            v[12] = std::cos(l.outer_angle); v[13] = 0.f; v[14] = 0.f; v[15] = 0.f;
        }
        ctx.gpu->SetUniform(spot_lights_uniform, buf, (uint16_t)(sc * 4));
    }

    if (light_counts_uniform != kGpuInvalidHandle)
    {
        float counts[4] = { (float)pc, (float)sc, 0.f, 0.f };
        ctx.gpu->SetUniform(light_counts_uniform, counts, 1);
    }
}

ke_result LightingManager::RecordLights(struct ke_frame_packet& packet, const ke_point_light *lights, uint32_t count)
{
    if (!lights && count > 0) return KE_ERROR_INVALID_ARGUMENT;
    if (count > packet.point_light_capacity) return KE_ERROR_OUT_OF_MEMORY;

    std::memcpy(packet.point_lights, lights, count * sizeof(ke_point_light));
    packet.point_light_count = count;

    point_lights_.assign(lights, lights + count);
    
    return KE_OK;
}

ke_result LightingManager::RecordSpotLights(struct ke_frame_packet& packet, const ke_spot_light *lights, uint32_t count)
{
    if (!lights && count > 0) return KE_ERROR_INVALID_ARGUMENT;
    if (count > packet.spot_light_capacity) return KE_ERROR_OUT_OF_MEMORY;

    std::memcpy(packet.spot_lights, lights, count * sizeof(ke_spot_light));
    packet.spot_light_count = count;

    spot_lights_.assign(lights, lights + count);

    return KE_OK;
}

ke_result LightingManager::CreateMaterial(RenderContext& ctx, const TextureManager& textures, const ke_material *mat, ke_material_handle *out_handle)
{
    if (!mat || !out_handle)
        return KE_RENDER_LOG_ERR(ctx.logger, KE_ERROR_INVALID_ARGUMENT, "CreateMaterial", "Invalid arguments");
    ke_texture_handle tex  = mat->albedo;
    ke_texture_handle nmap = mat->normal_map;
    // Default-constructed (idx=0) normal map means "no normal map" — handle 0 is
    // the built-in 1×1 white texture and decoding it as a tangent-space normal
    // (white pixel * 2 - 1 = +1+1+1) corrupts every face's lighting. The valid-
    // check `ke_texture_is_valid` keys off KE_HANDLE_NONE (UINT32_MAX), so we
    // promote the unset case here at the API boundary; albedo legitimately uses
    // handle 0 (white tint) and stays untouched.
    if (nmap.idx == 0) nmap.idx = KE_HANDLE_NONE;
    materials_.push_back({mat->r, mat->g, mat->b, mat->a, tex, mat->metallic, mat->roughness, nmap, true});
    *out_handle = {(uint32_t)(materials_.size() - 1)};
    return KE_OK;
}

ke_result LightingManager::DestroyMaterial(RenderContext& ctx, ke_material_handle handle)
{
    if (handle.idx >= (uint32_t)materials_.size())
        return KE_RENDER_LOG_ERR(ctx.logger, KE_ERROR_INVALID_ARGUMENT, "DestroyMaterial", "Invalid material handle");
    materials_[handle.idx].valid = false;
    return KE_OK;
}

void LightingManager::Shutdown()
{
    materials_.clear();
}

const MaterialEntry& LightingManager::GetMaterial(ke_material_handle handle) const
{
    static MaterialEntry s_invalid;
    if (handle.idx < (uint32_t)materials_.size()) return materials_[handle.idx];
    return s_invalid;
}

} // namespace kernel_engine::render::core
