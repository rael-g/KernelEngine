#pragma once

#include <kernel_engine/kernel/render/render.h>
#include <kernel_engine/kernel/logger/logger.h>
#include <kernel_engine/kernel/window/window.h>
#include <kernel_engine/render/bgfx/bgfx_render.h>
#include <bgfx/bgfx.h>
#include <string>

#include "InternalTypes.hpp"
#include "GeometryManager.hpp"
#include "TextureManager.hpp"
#include "LightingManager.hpp"
#include "ShadowPipeline.hpp"
#include "PostProcessPipeline.hpp"
#include "ClusteredForward.hpp"

namespace kernel_engine::render::bgfx
{

class BgfxLogCallback : public ::bgfx::CallbackI
{
public:
    void SetLogger(struct ke_logger *logger) { logger_ = logger; }

    virtual void fatal(const char *_filePath, uint16_t _line, ::bgfx::Fatal::Enum _code, const char *_str) override;
    virtual void traceVargs(const char *_filePath, uint16_t _line, const char *_format, va_list _argList) override;

    virtual void profilerBegin(const char*, uint32_t, const char*, uint16_t) override {}
    virtual void profilerBeginLiteral(const char*, uint32_t, const char*, uint16_t) override {}
    virtual void profilerEnd() override {}
    virtual uint32_t cacheReadSize(uint64_t) override { return 0; }
    virtual bool cacheRead(uint64_t, void*, uint32_t) override { return false; }
    virtual void cacheWrite(uint64_t, const void*, uint32_t) override {}
    virtual void screenShot(const char*, uint32_t, uint32_t, uint32_t, const void*, uint32_t, bool) override {}
    virtual void captureBegin(uint32_t, uint32_t, uint32_t, ::bgfx::TextureFormat::Enum, bool) override {}
    virtual void captureEnd() override {}
    virtual void captureFrame(const void*, uint32_t) override {}

private:
    struct ke_logger *logger_ = nullptr;
};

class KE_RENDER_API BgfxRenderer : 
    public GeometryManager, 
    public TextureManager, 
    public LightingManager,
    public ShadowPipeline,
    public PostProcessPipeline,
    public ClusteredForward
{
    friend class GeometryManager;
    friend class TextureManager;
    friend class LightingManager;
    friend class ShadowPipeline;
    friend class PostProcessPipeline;
    friend class ClusteredForward;

public:
    explicit BgfxRenderer(const ke_render_bgfx_params *params);
    ~BgfxRenderer();

    ke_result OnInitialize();
    ke_result OnShutdown();
    ke_result Frame();

    ke_result SetOrthographic(ke_bool enabled);
    ke_result ClearColor(float r, float g, float b, float a);
    ke_result SetViewTransform(const ke_mat4 *view, const ke_mat4 *proj);
    ke_result SetCameraPos(float x, float y, float z);

    ke_render *ToApi();

    // Test support
    void set_bgfx(class BgfxBackend* bgfx);
    class BgfxBackend* release_bgfx();

protected:
    virtual ::bgfx::ShaderHandle LoadShader(const char *name);
    virtual ke_result SetupShader();

    uint16_t program_             = kInvalidHandle;
    uint16_t depth_program_       = kInvalidHandle;
    uint16_t cull_program_        = kInvalidHandle;
    uint16_t skybox_program_      = kInvalidHandle;
    uint16_t bright_pass_program_ = kInvalidHandle;
    uint16_t blur_program_        = kInvalidHandle;
    uint16_t tonemap_program_     = kInvalidHandle;
    uint16_t prepass_program_     = kInvalidHandle;
    uint16_t ssao_program_        = kInvalidHandle;
    uint16_t ssao_blur_program_   = kInvalidHandle;
    uint16_t shadow_program_      = kInvalidHandle;

    BgfxLogCallback callback_;
    class BgfxBackend* bgfx_ = nullptr;
    bool own_bgfx_ = true; // internal flag for backend ownership
    bool initialized_ = false;

    ke_render render_api_{};
    struct ke_window* window_ = nullptr;
    ke_allocator *allocator_ = nullptr;
    ke_logger *logger_ = nullptr;
    std::string shader_path_;
    bool orthographic_ = true;

    float near_z_ = 0.1f;
    float far_z_  = 1000.0f;
    
    int32_t view_w_ = 0, view_h_ = 0;
    float last_view_[16]{};
    float last_proj_[16]{};
};

} // namespace kernel_engine::render::bgfx
