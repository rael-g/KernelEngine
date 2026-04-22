#include "shadow_pipeline.hpp"
#include "bgfx_renderer.hpp"
#include "bgfx_interface.hh"
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

ke_result ShadowPipeline::CreateShadowMap(uint32_t w, uint32_t h, ke_shadow_map_handle *out_handle)
{
    if (!out_handle || w == 0 || h == 0) return KE_ERROR_INVALID_ARGUMENT;
    auto* renderer = static_cast<BgfxRenderer*>(this);

    ::bgfx::TextureHandle color = renderer->bgfx_->CreateTexture2D(
        (uint16_t)w, (uint16_t)h, false, 1,
        ::bgfx::TextureFormat::R32F, BGFX_TEXTURE_RT);

    ::bgfx::TextureHandle depth = renderer->bgfx_->CreateTexture2D(
        (uint16_t)w, (uint16_t)h, false, 1,
        ::bgfx::TextureFormat::D16, BGFX_TEXTURE_RT_WRITE_ONLY);

    if (!::bgfx::isValid(color) || !::bgfx::isValid(depth))
    {
        if (::bgfx::isValid(color)) renderer->bgfx_->Destroy(color);
        if (::bgfx::isValid(depth)) renderer->bgfx_->Destroy(depth);
        return KE_ERROR_RENDER;
    }

    ::bgfx::TextureHandle attachments[2] = {color, depth};
    ::bgfx::FrameBufferHandle fb = renderer->bgfx_->CreateFrameBuffer(2, attachments, false);
    if (!::bgfx::isValid(fb))
    {
        renderer->bgfx_->Destroy(color);
        renderer->bgfx_->Destroy(depth);
        return KE_ERROR_RENDER;
    }

    shadow_maps_.push_back({color.idx, depth.idx, fb.idx, w, h, true});
    *out_handle = (ke_shadow_map_handle)(shadow_maps_.size() - 1);
    return KE_OK;
}

ke_result ShadowPipeline::DestroyShadowMap(ke_shadow_map_handle handle)
{
    if (handle >= (ke_shadow_map_handle)shadow_maps_.size() || !shadow_maps_[handle].valid)
        return KE_ERROR_INVALID_ARGUMENT;
    auto* renderer = static_cast<BgfxRenderer*>(this);
    auto &sm = shadow_maps_[handle];
    if (::bgfx::isValid(::bgfx::FrameBufferHandle{sm.fb}))   renderer->bgfx_->Destroy(::bgfx::FrameBufferHandle{sm.fb});
    if (::bgfx::isValid(::bgfx::TextureHandle{sm.depth_tex})) renderer->bgfx_->Destroy(::bgfx::TextureHandle{sm.depth_tex});
    if (::bgfx::isValid(::bgfx::TextureHandle{sm.color_tex})) renderer->bgfx_->Destroy(::bgfx::TextureHandle{sm.color_tex});
    sm = {};
    return KE_OK;
}

ke_result ShadowPipeline::BeginShadowPass(ke_shadow_map_handle handle,
                                              const ke_mat4 *light_view, const ke_mat4 *light_proj)
{
    if (handle >= (ke_shadow_map_handle)shadow_maps_.size() || !shadow_maps_[handle].valid)
        return KE_ERROR_INVALID_ARGUMENT;
    if (!light_view || !light_proj) return KE_ERROR_INVALID_ARGUMENT;

    auto* renderer = static_cast<BgfxRenderer*>(this);
    const auto &sm = shadow_maps_[handle];

    renderer->bgfx_->SetViewFrameBuffer(0, ::bgfx::FrameBufferHandle{sm.fb});
    renderer->bgfx_->SetViewRect(0, 0, 0, (uint16_t)sm.width, (uint16_t)sm.height);
    renderer->bgfx_->SetViewTransform(0, light_view->m, light_proj->m);

    renderer->bgfx_->SetPaletteColor(0, 1.0f, 0.0f, 0.0f, 0.0f);
    renderer->bgfx_->SetViewClearPalette(0, BGFX_CLEAR_COLOR | BGFX_CLEAR_DEPTH, 1.0f, 0, 0);

    active_shadow_handle_ = handle;
    MulMat4(light_view->m, light_proj->m, active_light_vp_);
    return KE_OK;
}

ke_result ShadowPipeline::SubmitMeshShadow(ke_mesh_handle mesh, const ke_mat4 *transform)
{
    auto* renderer = static_cast<BgfxRenderer*>(this);
    if (!::bgfx::isValid(::bgfx::ProgramHandle{renderer->shadow_program_})) return KE_ERROR_NOT_INITIALIZED;
    if (!transform) return KE_ERROR_INVALID_ARGUMENT;
    if (mesh >= (ke_mesh_handle)renderer->meshes_.size()) return KE_ERROR_INVALID_ARGUMENT;
    const auto &entry = renderer->meshes_[mesh];
    if (!::bgfx::isValid(::bgfx::VertexBufferHandle{entry.vb})) return KE_ERROR_INVALID_ARGUMENT;

    renderer->bgfx_->SetVertexBuffer(0, ::bgfx::VertexBufferHandle{entry.vb});
    renderer->bgfx_->SetIndexBuffer(::bgfx::IndexBufferHandle{entry.ib});
    renderer->bgfx_->SetTransform(transform->m);
    renderer->bgfx_->SetState(BGFX_STATE_WRITE_RGB | BGFX_STATE_WRITE_Z | BGFX_STATE_DEPTH_TEST_LESS);
    renderer->bgfx_->Submit(0, ::bgfx::ProgramHandle{renderer->shadow_program_});
    return KE_OK;
}

ke_result ShadowPipeline::EndShadowPass()
{
    return KE_OK;
}

ke_result ShadowPipeline::SetShadowMap(ke_shadow_map_handle handle)
{
    if (handle == KE_INVALID_SHADOW_MAP_HANDLE)
    {
        active_shadow_handle_ = kInvalidShadowHandle;
        return KE_OK;
    }
    if (handle >= (ke_shadow_map_handle)shadow_maps_.size() || !shadow_maps_[handle].valid)
        return KE_ERROR_INVALID_ARGUMENT;
    active_shadow_handle_ = handle;
    return KE_OK;
}

} // namespace kernel_engine::render::bgfx
