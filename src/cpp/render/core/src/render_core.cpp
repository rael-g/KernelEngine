#include <kernel_engine/render/core/render_core.h>
#include <native_systems.hpp>

extern "C" {

KE_RENDER_CORE_API void ke_render_core_shadow_system_set_map(ke_system_params* params, ke_shadow_map_handle handle)
{
    kernel_engine::render::core::ShadowSystem::SetShadowMap(params, handle);
}

KE_RENDER_CORE_API void ke_render_core_mesh_system_describe(uint32_t mesh_cid, uint32_t transform_cid, ke_system_params* out_params)
{
    if (out_params) *out_params = kernel_engine::render::core::MeshSystem::GetDescription(mesh_cid, transform_cid);
}

KE_RENDER_CORE_API void ke_render_core_light_system_describe(uint32_t light_cid, uint32_t point_cid, uint32_t spot_cid, uint32_t transform_cid, ke_system_params* out_params)
{
    if (out_params) *out_params = kernel_engine::render::core::LightSystem::GetDescription(light_cid, point_cid, spot_cid, transform_cid);
}

KE_RENDER_CORE_API void ke_render_core_camera_system_describe(uint32_t camera_cid, uint32_t transform_cid, ke_system_params* out_params)
{
    if (out_params) *out_params = kernel_engine::render::core::CameraSystem::GetDescription(camera_cid, transform_cid);
}

KE_RENDER_CORE_API void ke_render_core_shadow_system_describe(uint32_t light_cid, uint32_t mesh_cid, uint32_t transform_cid, ke_system_params* out_params)
{
    if (out_params) *out_params = kernel_engine::render::core::ShadowSystem::GetDescription(light_cid, mesh_cid, transform_cid);
}

KE_RENDER_CORE_API void ke_render_core_skybox_system_describe(uint32_t skybox_cid, ke_system_params* out_params)
{
    if (out_params) *out_params = kernel_engine::render::core::SkyboxSystem::GetDescription(skybox_cid);
}

}
