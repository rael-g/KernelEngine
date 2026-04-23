#include "shadow_pipeline.hpp"
#include "geometry_manager.hpp"
#include "render_context.hpp"
#include "gpu_device.hpp"
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

    GpuTextureHandle color = ctx.gpu->CreateTexture2D(
        (uint16_t)w, (uint16_t)h, false, 1,
        14, 0x0000100000000000ULL, nullptr); // 14: R32F, 0x...: BGFX_TEXTURE_RT

    GpuTextureHandle depth = ctx.gpu->CreateTexture2D(
        (uint16_t)w, (uint16_t)h, false, 1,
        28, 0x0000200000000000ULL, nullptr); // 28: D16, 0x...: BGFX_TEXTURE_RT_WRITE_ONLY

    if (color == kGpuInvalidHandle || depth == kGpuInvalidHandle)
    {
        if (color != kGpuInvalidHandle) ctx.gpu->DestroyTexture(color);
        if (depth != kGpuInvalidHandle) ctx.gpu->DestroyTexture(depth);
        return KE_ERROR_RENDER;
    }

    GpuTextureHandle attachments[2] = {color, depth};
    GpuFrameBufferHandle fb = ctx.gpu->CreateFrameBuffer(2, attachments, false);
    if (fb == kGpuInvalidHandle)
    {
        ctx.gpu->DestroyTexture(color);
        ctx.gpu->DestroyTexture(depth);
        return KE_ERROR_RENDER;
    }

    shadow_maps_.push_back({color, depth, fb, w, h, true});
    *out_handle = (ke_shadow_map_handle)(shadow_maps_.size() - 1);
    return KE_OK;
}

ke_result ShadowPipeline::DestroyShadowMap(RenderContext& ctx, ke_shadow_map_handle handle)
{
    if (handle >= (ke_shadow_map_handle)shadow_maps_.size() || !shadow_maps_[handle].valid || !ctx.gpu)
        return KE_ERROR_INVALID_ARGUMENT;
    auto &sm = shadow_maps_[handle];
    if (sm.fb != kGpuInvalidHandle)        ctx.gpu->DestroyFrameBuffer(sm.fb);
    if (sm.depth_tex != kGpuInvalidHandle) ctx.gpu->DestroyTexture(sm.depth_tex);
    if (sm.color_tex != kGpuInvalidHandle) ctx.gpu->DestroyTexture(sm.color_tex);
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

    ctx.gpu->SetViewFrameBuffer(kDepthView, sm.fb);
    ctx.gpu->SetViewRect(kDepthView, 0, 0, (uint16_t)sm.width, (uint16_t)sm.height);
    ctx.gpu->SetViewTransform(kDepthView, light_view->m, light_proj->m);

    ctx.gpu->SetPaletteColor(0, 1.0f, 0.0f, 0.0f, 0.0f);
    // BGFX_CLEAR_COLOR | BGFX_CLEAR_DEPTH
    ctx.gpu->SetViewClear(kDepthView, 0x0001 | 0x0002, 1.0f, 0, 0);

    active_shadow_handle = handle;
    MulMat4(light_view->m, light_proj->m, active_light_vp);
    return KE_OK;
}

ke_result ShadowPipeline::SubmitMeshShadow(RenderContext& ctx, const GeometryManager& geometry, GpuProgramHandle shadow_program, ke_mesh_handle mesh, const ke_mat4 *transform)
{
    if (!ctx.gpu) return KE_ERROR_RENDER;
    if (shadow_program == kGpuInvalidHandle) return KE_ERROR_NOT_INITIALIZED;
    if (!transform) return KE_ERROR_INVALID_ARGUMENT;
    
    const auto& entry = geometry.GetMeshEntry(mesh);
    if (entry.vb == kGpuInvalidHandle) return KE_ERROR_INVALID_ARGUMENT;

    ctx.gpu->SetVertexBuffer(0, entry.vb);
    ctx.gpu->SetIndexBufferStatic(entry.ib);
    ctx.gpu->SetTransform(transform->m, 1);
    // BGFX_STATE_WRITE_RGB | BGFX_STATE_WRITE_Z | BGFX_STATE_DEPTH_TEST_LESS
    ctx.gpu->SetState(0x0000000000000001ULL | 0x0000000000000400ULL | 0x0000000000000010ULL, 0);
    ctx.gpu->Submit(kDepthView, shadow_program, 0, false);
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
    shadow_maps_.clear();
}

GpuTextureHandle ShadowPipeline::GetActiveShadowMapTex() const
{
    if (active_shadow_handle < shadow_maps_.size()) return shadow_maps_[active_shadow_handle].color_tex;
    return kGpuInvalidHandle;
}

} // namespace kernel_engine::render::bgfx
