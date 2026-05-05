#include "../include/shadow_pipeline.hpp"
#include "../include/geometry_manager.hpp"
#include "render_context.hpp"
#include "gpu_device.hpp"
#include <cstring>
#include <algorithm>

namespace kernel_engine::render::bgfx
{

ke_result ShadowPipeline::CreateShadowMap(RenderContext& ctx, uint32_t w, uint32_t h, ke_shadow_map_handle *out)
{
    if (!out || w == 0 || h == 0 || !ctx.gpu) return KE_ERROR_INVALID_ARGUMENT;

    GpuTextureHandle depth_tex = ctx.gpu->CreateTexture2D((uint16_t)w, (uint16_t)h, false, 1, kTexFmtD16, kTexFlagRT, nullptr);
    if (depth_tex == kGpuInvalidHandle) return KE_ERROR_RENDER;

    GpuFrameBufferHandle fb = ctx.gpu->CreateFrameBuffer(1, &depth_tex, true);
    if (fb == kGpuInvalidHandle) return KE_ERROR_RENDER;

    ShadowMapEntry entry;
    entry.fb = fb;
    entry.depth_tex = depth_tex;
    entry.w = w;
    entry.h = h;
    entry.valid = true;

    shadow_maps_.push_back(entry);
    *out = {(uint32_t)(shadow_maps_.size() - 1)};
    return KE_OK;
}

ke_result ShadowPipeline::DestroyShadowMap(RenderContext& ctx, ke_shadow_map_handle h)
{
    if (h.idx >= (uint32_t)shadow_maps_.size() || !ctx.gpu) return KE_ERROR_INVALID_ARGUMENT;
    if (shadow_maps_[h.idx].fb != kGpuInvalidHandle) ctx.gpu->DestroyFrameBuffer(shadow_maps_[h.idx].fb);
    shadow_maps_[h.idx].valid = false;
    return KE_OK;
}

ke_result ShadowPipeline::BeginShadowPass(RenderContext& ctx, ke_shadow_map_handle h, const ke_mat4 *v, const ke_mat4 *p)
{
    if (h.idx >= (uint32_t)shadow_maps_.size() || !v || !p || !ctx.gpu) return KE_ERROR_INVALID_ARGUMENT;
    auto &entry = shadow_maps_[h.idx];
    if (!entry.valid) return KE_ERROR_INVALID_ARGUMENT;

    active_shadow_handle = h;
    ctx.gpu->SetViewFrameBuffer(3 /*SHADOW*/, entry.fb);
    ctx.gpu->SetViewRect(3, 0, 0, (uint16_t)entry.w, (uint16_t)entry.h);
    ctx.gpu->SetViewClear(3, 0x0002 /*DEPTH*/, 0, 1.0f, 0);
    ctx.gpu->SetViewTransform(3, v->m, p->m);

    return KE_OK;
}

ke_result ShadowPipeline::SubmitMeshShadow(RenderContext& ctx, const GeometryManager& geom, GpuProgramHandle prog, ke_mesh_handle m, const ke_mat4 *t)
{
    if (!ctx.gpu || prog == kGpuInvalidHandle || !t) return KE_ERROR_RENDER;
    const auto &entry = geom.GetMeshEntry(m);
    if (entry.vb == kGpuInvalidHandle) return KE_ERROR_INVALID_ARGUMENT;

    ctx.gpu->SetTransform(t->m, 1);
    ctx.gpu->SetVertexBuffer(0, entry.vb);
    ctx.gpu->SetIndexBufferStatic(entry.ib);
    // BGFX_STATE_WRITE_Z | BGFX_STATE_DEPTH_TEST_LESS
    ctx.gpu->SetState(0x0000001000000000ULL | 0x0000000000000010ULL, 0);
    ctx.gpu->Submit(3 /*SHADOW*/, prog, 0, false);

    return KE_OK;
}

ke_result ShadowPipeline::EndShadowPass(RenderContext& ctx)
{
    active_shadow_handle = KE_SHADOW_MAP_NONE;
    return KE_OK;
}

ke_result ShadowPipeline::SetShadowMap(RenderContext& ctx, ke_shadow_map_handle h)
{
    if (h.idx >= (uint32_t)shadow_maps_.size()) return KE_ERROR_INVALID_ARGUMENT;
    active_shadow_handle = h;
    return KE_OK;
}

GpuTextureHandle ShadowPipeline::GetActiveShadowTex() const
{
    if (active_shadow_handle.idx < (uint32_t)shadow_maps_.size())
        return shadow_maps_[active_shadow_handle.idx].depth_tex;
    return kGpuInvalidHandle;
}

void ShadowPipeline::Shutdown()
{
    shadow_maps_.clear();
}

} // namespace kernel_engine::render::bgfx
