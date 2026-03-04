#pragma once

#include <cstdint>
#include <kernel_engine/core/common/descriptor.h>
#include <kernel_engine/core/engine/frame.h>
#include <kernel_engine/core/engine/system.h>
#include <kernel_engine/core/logger/logger.h>
#include <kernel_engine/core/render/render.h>
#include <kernel_engine/render/bgfx/render_plugin.hh>
#include <string>

struct ke_window;

namespace kernel_engine::render::bgfx
{

class BgfxRenderSystem
{
  public:
    explicit BgfxRenderSystem(const ke_render_bgfx_descriptor *desc);
    ~BgfxRenderSystem();

    [[nodiscard]] uint64_t Id() const;

    ke_result OnInitialize();
    ke_result OnShutdown();
    static ke_result OnUpdate(const ke_frame &frame);

    // Render operations
    ke_result SetOrthographic(bool enabled);
    ke_result ClearColor(float r, float g, float b, float a);
    static ke_result DrawNode(void *node_handle);
    static ke_result SetNodeShape(void *node_handle, int shape);
    static ke_result SetNodeColor(void *node_handle, float r, float g, float b, float a);

    ke_system *ToApi();

  private:
    ke_result SetupShader();
    void *LoadShader(const char *name);

    ke_system engine_api_{};
    ke_render render_api_{};

    struct ke_window* window_ = nullptr;
    ke_allocator *allocator_ = nullptr;
    ke_logger *logger_ = nullptr;
    std::string shader_path_;
    uint32_t clear_color_ = 0x303030ff;
    bool orthographic_ = true;

    uint16_t program_ = 0; // bgfx::ProgramHandle is a struct wrapping uint16_t
};

} // namespace kernel_engine::render::bgfx
