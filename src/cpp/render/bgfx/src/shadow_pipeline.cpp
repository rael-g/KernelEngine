#include "shadow_pipeline.hpp"
#include "geometry_manager.hpp"
#include "render_context.hpp"
#include "gpu_device.hpp"
#include <bgfx/bgfx.h>
#include <vector>
#include <cstring>

namespace kernel_engine::render::bgfx
{

static void MulMat4(const float *a, const float *b, float *r)
{
    for (int i = 0; i < 4; ++i)
        for (int j = 0; j < 4; ++j)
        {
            r[i * 4 + j] = 0.f;
            for (int k = 0; k < 4; ++k)
                r[i * 4 + j] += a[i * 4 + k] * b[k * 4 + j];
        }
}

ke_result ShadowPipeline::CreateShadowMap(RenderContext& ctx, uint32_t w, uint32_t h, ke_shadow_map_handle *out_handle)
{
    if (!out_handle || w == 0 || h == 0 || !ctx.gpu) return KE_ERROR_INVALID_ARGUMENT;

    ::bgfx::TextureHandle color = ctx.gpu->CreateTexture2D(
        (uint16_t)w, (uint16_t)h, false, 1,
        ::bgfx::TextureFormat::R32F, BGFX_TEXTURE_RT, nullptr);

    ::bgfx::TextureHandle depth = ctx.gpu->CreateTexture2D(
        (uint16_t)w, (uint16_t)h, false, 1,
        ::bgfx::TextureFormat::D16, BGFX_TEXTURE_RT_WRITE_ONLY, nullptr);

    if (!::bgfx::isValid(color) || !::bgfx::isValid(depth))
    {
        if (::bgfx::isValid(color)) ctx.gpu->Destroy(color);
        if (::bgfx::isValid(depth)) ctx.gpu->Destroy(depth);
        return KE_ERROR_RENDER;
    }

    ::bgfx::TextureHandle attachments[2] = {color, depth};
    ::bgfx::FrameBufferHandle fb = ctx.gpu->CreateFrameBuffer(2, attachments, false);
    if (!::bgfx::isValid(fb))
    {
        ctx.gpu->Destroy(color);
        ctx.gpu->Destroy(depth);
        return KE_ERROR_RENDER;
    }

    shadow_maps_.push_back({color.idx, depth.idx, fb.idx, w, h, true});
    *out_handle = (ke_shadow_map_handle)(shadow_maps_.size() - 1);
    return KE_OK;
}

ke_result ShadowPipeline::DestroyShadowMap(RenderContext& ctx, ke_shadow_map_handle handle)
{
    if (handle >= (ke_shadow_map_handle)shadow_maps_.size() || !shadow_maps_[handle].valid || !ctx.gpu)
        return KE_ERROR_INVALID_ARGUMENT;
    auto &sm = shadow_maps_[handle];
    if (::bgfx::isValid(::bgfx::FrameBufferHandle{sm.fb}))   ctx.gpu->Destroy(::bgfx::FrameBufferHandle{sm.fb});
    if (::bgfx::isValid(::bgfx::TextureHandle{sm.depth_tex})) ctx.gpu->Destroy(::bgfx::TextureHandle{sm.depth_tex});
    if (::bgfx::isValid(::bgfx::TextureHandle{sm.color_tex})) ctx.gpu->Destroy(::bgfx::TextureHandle{sm.color_tex});
    sm = {};
    return KE_OK;
}

ke_result ShadowPipeline::BeginShadowPass(RenderContext& ctx, ke_shadow_map_handle handle,
                                              const ke_mat4 *light_view, const ke_mat4 *light_proj)
{
    if (handle >= (ke_shadow_map_handle)shadow_maps_.size() || !shadow_maps_[handle].valid || !ctx.gpu)
        return KE_ERROR_INVALID_ARGUMENT;
    if (!light_view || !light_proj) return KE_ERROR_INVALID_ARGUMENT;

    const auto &sm = shadow_maps_[handle];

    ctx.gpu->SetViewFrameBuffer(kDepthView, ::bgfx::FrameBufferHandle{sm.fb});
    ctx.gpu->SetViewRect(kDepthView, 0, 0, (uint16_t)sm.width, (uint16_t)sm.height);
    ctx.gpu->SetViewTransform(kDepthView, light_view->m, light_proj->m);

    ctx.gpu->SetPaletteColor(0, 1.0f, 0.0f, 0.0f, 0.0f);
    ctx.gpu->SetViewClear(kDepthView, BGFX_CLEAR_COLOR | BGFX_CLEAR_DEPTH, 1.0f, 0, 0);

    active_shadow_handle = handle;
    MulMat4(light_view->m, light_proj->m, active_light_vp);
    return KE_OK;
}

ke_result ShadowPipeline::SubmitMeshShadow(RenderContext& ctx, const GeometryManager& geometry, uint16_t shadow_program, ke_mesh_handle mesh, const ke_mat4 *transform)
{
    if (!ctx.gpu) return KE_ERROR_RENDER;
    if (!::bgfx::isValid(::bgfx::ProgramHandle{shadow_program})) return KE_ERROR_NOT_INITIALIZED;
    if (!transform) return KE_ERROR_INVALID_ARGUMENT;
    
    const auto& entry = geometry.GetMeshEntry(mesh);
    if (!::bgfx::isValid(::bgfx::VertexBufferHandle{entry.vb})) return KE_ERROR_INVALID_ARGUMENT;

    ctx.gpu->SetVertexBuffer(0, ::bgfx::VertexBufferHandle{entry.vb});
    ctx.gpu->SetIndexBuffer(::bgfx::IndexBufferHandle{entry.ib});
    ctx.gpu->SetTransform(transform->m, 1);
    ctx.gpu->SetState(BGFX_STATE_WRITE_RGB | BGFX_STATE_WRITE_Z | BGFX_STATE_DEPTH_TEST_LESS, 0);
    ctx.gpu->Submit(kDepthView, ::bgfx::ProgramHandle{shadow_program}, 0, false);
    return KE_OK;
}

ke_result ShadowPipeline::EndShadowPass(RenderContext& ctx)
{
    return KE_OK;
}

ke_result ShadowPipeline::SetShadowMap(RenderContext& ctx, ke_shadow_map_handle handle)
{
    if (handle == KE_INVALID_SHADOW_MAP_HANDLE)
    {
        active_shadow_handle = kInvalidShadowHandle;
        return KE_OK;
    }
    if (handle >= (ke_shadow_map_handle)shadow_maps_.size() || !shadow_maps_[handle].valid)
        return KE_ERROR_INVALID_ARGUMENT;
    active_shadow_handle = handle;
    return KE_OK;
}

void ShadowPipeline::Shutdown()
{
    // GPU device handles cleanup
    shadow_maps_.clear();
}

uint16_t ShadowPipeline::GetActiveShadowMapTex() const
{
    if (active_shadow_handle < shadow_maps_.size()) return shadow_maps_[active_shadow_handle].color_tex;
    return kInvalidHandle;
}

} // namespace kernel_engine::render::bgfx
