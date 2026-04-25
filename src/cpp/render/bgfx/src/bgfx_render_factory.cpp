#include <kernel_engine/render/bgfx/bgfx_render.h>
#include <kernel_engine/kernel/render/render.h>
#include <kernel_engine/kernel/world/system.h>
#include <core_renderer.hpp>
#include <native_systems.hpp>
#include <kernel_engine/kernel/context/allocator.h>
#include <new>

extern "C" {
    KE_RENDER_API ke_result ke_render_bgfx_create(const ke_render_bgfx_params *params, ke_render **out_render) {
        if (!out_render || !params || !params->allocator) return KE_ERROR_INVALID_ARGUMENT;
        void *mem = params->allocator->alloc(params->allocator, sizeof(kernel_engine::render::bgfx::CoreRenderer), alignof(kernel_engine::render::bgfx::CoreRenderer));
        if (!mem) return KE_ERROR_OUT_OF_MEMORY;
        
        kernel_engine::render::bgfx::GpuRendererParams core_params = {
            params->allocator,
            params->logger,
            params->shader_path,
            params->window,
            params->renderer_type
        };
        
        auto *renderer = new (mem) kernel_engine::render::bgfx::CoreRenderer(core_params);
        *out_render = renderer->ToApi();
        return KE_OK;
    }

    KE_RENDER_API ke_result ke_render_bgfx_create_mesh_system_desc(uint32_t mesh_cid, uint32_t transform_cid, ke_system_desc *out_desc) {
        if (!out_desc) return KE_ERROR_INVALID_ARGUMENT;
        *out_desc = kernel_engine::render::bgfx::MeshSystem::GetDescription(mesh_cid, transform_cid);
        return KE_OK;
    }

    KE_RENDER_API ke_result ke_render_bgfx_create_light_system_desc(uint32_t light_cid, uint32_t point_cid, uint32_t spot_cid, uint32_t transform_cid, ke_system_desc *out_desc) {
        if (!out_desc) return KE_ERROR_INVALID_ARGUMENT;
        *out_desc = kernel_engine::render::bgfx::LightSystem::GetDescription(light_cid, point_cid, spot_cid, transform_cid);
        return KE_OK;
    }

    KE_RENDER_API ke_result ke_render_bgfx_create_camera_system_desc(uint32_t camera_cid, uint32_t transform_cid, ke_system_desc *out_desc) {
        if (!out_desc) return KE_ERROR_INVALID_ARGUMENT;
        *out_desc = kernel_engine::render::bgfx::CameraSystem::GetDescription(camera_cid, transform_cid);
        return KE_OK;
    }

    KE_RENDER_API ke_result ke_render_bgfx_create_shadow_system_desc(uint32_t light_cid, uint32_t mesh_cid, uint32_t transform_cid, ke_system_desc *out_desc) {
        if (!out_desc) return KE_ERROR_INVALID_ARGUMENT;
        *out_desc = kernel_engine::render::bgfx::ShadowSystem::GetDescription(light_cid, mesh_cid, transform_cid);
        return KE_OK;
    }

    KE_RENDER_API ke_result ke_render_bgfx_create_skybox_system_desc(uint32_t skybox_cid, ke_system_desc *out_desc) {
        if (!out_desc) return KE_ERROR_INVALID_ARGUMENT;
        *out_desc = kernel_engine::render::bgfx::SkyboxSystem::GetDescription(skybox_cid);
        return KE_OK;
    }
}
