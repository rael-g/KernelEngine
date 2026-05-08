#include <kernel_engine/render/bgfx/bgfx_render.h>
#include <kernel_engine/kernel/render/render.h>
#include <kernel_engine/kernel/world/system.h>
#include <core_renderer.hpp>
#include <gpu_device.hpp>
#include <native_systems.hpp>
#include <render_logging.hpp>
#include <kernel_engine/kernel/context/allocator.h>
#include <bgfx/bgfx.h>
#include <new>

using namespace kernel_engine::render::bgfx;

extern "C" {
    KE_RENDER_API ke_result ke_render_bgfx_create(const ke_render_bgfx_params *params, ke_render **out_render) {
        if (!out_render || !params || !params->allocator) return KE_ERROR_INVALID_ARGUMENT;

        auto* alloc = params->allocator;

        void* device_mem = alloc->alloc(alloc, sizeof(kernel_engine::render::bgfx::BgfxGpuDevice), alignof(kernel_engine::render::bgfx::BgfxGpuDevice));
        if (!device_mem) return KE_RENDER_LOG_ERR(params->logger, KE_ERROR_OUT_OF_MEMORY, "ke_render_bgfx_create", "Failed to allocate BgfxGpuDevice");
        auto* device = new (device_mem) kernel_engine::render::bgfx::BgfxGpuDevice();

        // renderer_type == 0 means "use engine default" → Vulkan
        uint32_t renderer_type = params->renderer_type == 0
            ? (uint32_t)::bgfx::RendererType::Vulkan
            : params->renderer_type;

        kernel_engine::render::bgfx::GpuRendererParams core_params = {
            params->allocator,
            params->logger,
            params->shader_path,
            params->window,
            renderer_type,
            params->vsync != 0
        };

        void* renderer_mem = alloc->alloc(alloc, sizeof(kernel_engine::render::bgfx::CoreRenderer), alignof(kernel_engine::render::bgfx::CoreRenderer));
        if (!renderer_mem) {
            alloc->free(alloc, device_mem);
            return KE_RENDER_LOG_ERR(params->logger, KE_ERROR_OUT_OF_MEMORY, "ke_render_bgfx_create", "Failed to allocate CoreRenderer");
        }
        auto* renderer = new (renderer_mem) kernel_engine::render::bgfx::CoreRenderer(core_params);
        renderer->SetGpuDevice(device);

        *out_render = renderer->ToApi();
        return KE_OK;
    }

    KE_RENDER_API const char* ke_render_bgfx_get_last_fatal_error() {
        return kernel_engine::render::bgfx::GetLastFatalError();
    }

    KE_RENDER_API ke_result ke_render_bgfx_create_mesh_system_params(uint32_t mesh_cid, uint32_t transform_cid, ke_system_params *out_params) {
        if (!out_params) return KE_ERROR_INVALID_ARGUMENT;
        *out_params = kernel_engine::render::bgfx::MeshSystem::GetDescription(mesh_cid, transform_cid);
        return KE_OK;
    }

    KE_RENDER_API ke_result ke_render_bgfx_create_light_system_params(uint32_t light_cid, uint32_t point_cid, uint32_t spot_cid, uint32_t transform_cid, ke_system_params *out_params) {
        if (!out_params) return KE_ERROR_INVALID_ARGUMENT;
        *out_params = kernel_engine::render::bgfx::LightSystem::GetDescription(light_cid, point_cid, spot_cid, transform_cid);
        return KE_OK;
    }

    KE_RENDER_API ke_result ke_render_bgfx_create_camera_system_params(uint32_t camera_cid, uint32_t transform_cid, ke_system_params *out_params) {
        if (!out_params) return KE_ERROR_INVALID_ARGUMENT;
        *out_params = kernel_engine::render::bgfx::CameraSystem::GetDescription(camera_cid, transform_cid);
        return KE_OK;
    }

    KE_RENDER_API ke_result ke_render_bgfx_create_shadow_system_params(uint32_t light_cid, uint32_t mesh_cid, uint32_t transform_cid, ke_system_params *out_params) {
        if (!out_params) return KE_ERROR_INVALID_ARGUMENT;
        *out_params = kernel_engine::render::bgfx::ShadowSystem::GetDescription(light_cid, mesh_cid, transform_cid);
        return KE_OK;
    }

    KE_RENDER_API ke_result ke_render_bgfx_create_skybox_system_params(uint32_t skybox_cid, ke_system_params *out_params) {
        if (!out_params) return KE_ERROR_INVALID_ARGUMENT;
        *out_params = kernel_engine::render::bgfx::SkyboxSystem::GetDescription(skybox_cid);
        return KE_OK;
    }

    KE_RENDER_API void ke_render_bgfx_shadow_system_set_map(ke_system_params *params, ke_shadow_map_handle handle) {
        kernel_engine::render::bgfx::ShadowSystem::SetShadowMap(params, handle);
    }
}
