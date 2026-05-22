#include "shadow_pipeline.hpp"
#include <render_logging.hpp>
#include "geometry_manager.hpp"
#include "render_context.hpp"
#include "gpu_device.hpp"
#include "view_ids.hpp"
#include <cstring>
#include <algorithm>


namespace kernel_engine::render::core
{

ke_result ShadowPipeline::CreateShadowMap(RenderContext& ctx, uint32_t w, uint32_t h, ke_shadow_map_handle *out)
{
    if (!out || w == 0 || h == 0 || !ctx.gpu)
        return KE_RENDER_LOG_ERR(ctx.logger, KE_ERROR_INVALID_ARGUMENT, "CreateShadowMap", "Invalid arguments or GPU not set");

    // The shadow map is SAMPLED as an R32F color target: fs_shadow writes gl_FragCoord.z into it,
    // and the scene shader samples that value. A D16 depth attachment backs the depth test. A
    // depth-only FB does not work here because fs_shadow outputs color (which would have no target)
    // and sampling a raw D16 depth texture is not portable across backends.
    GpuTextureHandle color_tex = ctx.gpu->CreateTexture2D((uint16_t)w, (uint16_t)h, false, 1, kTexFmtR32F, kTexFlagRT, nullptr);
    if (color_tex == kGpuInvalidHandle)
        return KE_RENDER_LOG_ERR(ctx.logger, KE_ERROR_RENDER, "CreateShadowMap", "GPU color texture creation failed");

    GpuTextureHandle depth_tex = ctx.gpu->CreateTexture2D((uint16_t)w, (uint16_t)h, false, 1, kTexFmtD16, kTexFlagRT, nullptr);
    if (depth_tex == kGpuInvalidHandle)
        return KE_RENDER_LOG_ERR(ctx.logger, KE_ERROR_RENDER, "CreateShadowMap", "GPU depth texture creation failed");

    GpuTextureHandle attachments[2] = { color_tex, depth_tex };
    GpuFrameBufferHandle fb = ctx.gpu->CreateFrameBuffer(2, attachments, true);
    if (fb == kGpuInvalidHandle)
        return KE_RENDER_LOG_ERR(ctx.logger, KE_ERROR_RENDER, "CreateShadowMap", "GPU framebuffer creation failed");

    ShadowMapEntry entry;
    entry.fb = fb;
    entry.depth_tex = color_tex; // scene samples the R32F color target (where fs_shadow stored depth)
    entry.w = w;
    entry.h = h;
    entry.valid = true;

    shadow_maps_.push_back(entry);
    *out = {(uint32_t)(shadow_maps_.size() - 1)};
    return KE_OK;
}

ke_result ShadowPipeline::DestroyShadowMap(RenderContext& ctx, ke_shadow_map_handle h)
{
    if (h.idx >= (uint32_t)shadow_maps_.size() || !ctx.gpu)
        return KE_RENDER_LOG_ERR(ctx.logger, KE_ERROR_INVALID_ARGUMENT, "DestroyShadowMap", "Invalid handle or GPU not set");
    if (shadow_maps_[h.idx].fb != kGpuInvalidHandle) ctx.gpu->DestroyFrameBuffer(shadow_maps_[h.idx].fb);
    shadow_maps_[h.idx].valid = false;
    return KE_OK;
}

ke_result ShadowPipeline::BeginShadowPass(RenderContext& ctx, ke_shadow_map_handle h, const ke_mat4 *v, const ke_mat4 *p)
{
    if (h.idx >= (uint32_t)shadow_maps_.size() || !v || !p || !ctx.gpu)
        return KE_RENDER_LOG_ERR(ctx.logger, KE_ERROR_INVALID_ARGUMENT, "BeginShadowPass", "Invalid arguments or GPU not set");
    auto &entry = shadow_maps_[h.idx];
    if (!entry.valid)
        return KE_RENDER_LOG_ERR(ctx.logger, KE_ERROR_INVALID_ARGUMENT, "BeginShadowPass", "Shadow map not valid");

    active_shadow_handle = h;
    // View 0 (SHADOW): MUST be lower than the scene view (1) so bgfx renders the shadow depth
    // BEFORE the scene samples it in the same frame. On view 3 the scene (view 1) ran first and
    // read the cleared (1.0) depth → ComputeShadow never found occlusion → no shadow. View 0 is
    // otherwise unused (the depth prepass is not implemented).
    ctx.gpu->SetViewFrameBuffer(Id(ViewId::Shadow), entry.fb);
    ctx.gpu->SetViewRect(Id(ViewId::Shadow), 0, 0, (uint16_t)entry.w, (uint16_t)entry.h);
    // Clear COLOR to 1.0 (far) — the R32F target stores depth — and clear DEPTH for the test.
    ctx.gpu->SetViewClear(Id(ViewId::Shadow), GpuClearFlags::Color | GpuClearFlags::Depth, 0xFFFFFFFF, 1.0f, 0);
    ctx.gpu->SetViewTransform(Id(ViewId::Shadow), v->m, p->m);

    // Propagate light VP + shadow-enabled flag to the main scene shader uniforms.
    // Without this, vs_basic computes v_shadowCoord = mul(0, worldPos) = 0 and the
    // main pass either ignores shadow or returns NaN coordinates → tudo na sombra.
    // NOTE: ke_mat4_mul(out, a, b) computes out = b*a (verified: translation*rotation yields
    // translate-then-rotate). The scene shader does mul(u_lightVP, worldPos) = u_lightVP*worldPos
    // (M*v), so u_lightVP must be proj*view. To get proj*view we therefore pass (v, p).
    ke_mat4 light_vp;
    ke_mat4_mul(&light_vp, v, p);
    if (light_vp_uniform != kGpuInvalidHandle)
        ctx.gpu->SetUniform(light_vp_uniform, light_vp.m, 1);
    if (shadow_params_uniform != kGpuInvalidHandle) {
        float sp[4] = { 1.0f, 0.0f, 0.0f, 0.0f }; // x = shadow-enabled
        ctx.gpu->SetUniform(shadow_params_uniform, sp, 1);
    }

    return KE_OK;
}

ke_result ShadowPipeline::SubmitMeshShadow(RenderContext& ctx, const GeometryManager& geom, GpuProgramHandle prog, ke_mesh_handle m, const ke_mat4 *t)
{
    if (!ctx.gpu || prog == kGpuInvalidHandle || !t)
        return KE_RENDER_LOG_ERR(ctx.logger, KE_ERROR_RENDER, "SubmitMeshShadow", "Invalid arguments or program");
    const auto &entry = geom.GetMeshEntry(m);
    if (entry.vb == kGpuInvalidHandle)
        return KE_RENDER_LOG_ERR(ctx.logger, KE_ERROR_INVALID_ARGUMENT, "SubmitMeshShadow", "Invalid mesh entry");

    ctx.gpu->SetTransform(t->m, 1);
    ctx.gpu->SetVertexBuffer(0, entry.vb);
    ctx.gpu->SetIndexBufferStatic(entry.ib);
    // BGFX_STATE_WRITE_RGBA (0x0F) | BGFX_STATE_DEPTH_TEST_LESS (0x10) | BGFX_STATE_WRITE_Z (0x40<<32).
    // WRITE_R carries fs_shadow's gl_FragCoord.z into the R32F target; WRITE_Z populates the depth
    // attachment for the test. The previous value (0x10<<32) was neither a real WRITE_Z nor a color
    // write, so the shadow map was never written and stayed at its clear value (no shadow ever).
    ctx.gpu->SetState(GpuStateFlags::WriteRgba | GpuStateFlags::WriteZ | GpuStateFlags::DepthTestLess, 0);
    ctx.gpu->Submit(Id(ViewId::Shadow), prog, 0, false);

    return KE_OK;
}

ke_result ShadowPipeline::EndShadowPass(RenderContext& ctx)
{
    // Intentionally a no-op: active_shadow_handle MUST remain set so the main scene pass (which runs
    // after this in FrameSubmitter) can bind the shadow depth texture via GetActiveShadowTex().
    // Resetting it here left s_shadowMap on the white fallback → ComputeShadow always returned 1.0
    // (no shadow ever). The handle is re-set every frame by BeginShadowPass.
    (void)ctx;
    return KE_OK;
}

ke_result ShadowPipeline::SetShadowMap(RenderContext& ctx, ke_shadow_map_handle h)
{
    if (h.idx >= (uint32_t)shadow_maps_.size())
        return KE_RENDER_LOG_ERR(ctx.logger, KE_ERROR_INVALID_ARGUMENT, "SetShadowMap", "Invalid handle");
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

} // namespace kernel_engine::render::core
