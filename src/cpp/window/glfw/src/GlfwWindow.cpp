#include "GlfwWindow.hpp"
#include "GlfwInterface.hpp"
#include "InternalHelpers.hpp"
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/input/input_messages.h>
#include <new>
#include <cstring>

#define GLFW_EXPOSE_NATIVE_WIN32
#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>

namespace kernel_engine::window::glfw
{

using namespace detail;

static GlfwBackend* s_glfw_backend = nullptr;

#ifdef _WIN32
void* RealGlfwBackend::GetWin32Window(GLFWwindow* window) {
    return (void*)(uintptr_t)glfwGetWin32Window(window);
}
#endif

static void glfw_key_callback(GLFWwindow *window, int key, int scancode, int action, int mods)
{
    (void)scancode;
    (void)mods;
    if (!s_glfw_backend) return;
    auto *win = static_cast<GlfwWindow *>(s_glfw_backend->GetWindowUserPointer(window));
    if ((win != nullptr) && (win->GetPipe() != nullptr))
    {
        ke_msg_key_event msg = {(int32_t)key, (int32_t)action};
        win->GetPipe()->broadcast(win->GetPipe(), KE_MSG_KEY_EVENT, &msg, sizeof(msg));
    }
}

GlfwWindow::GlfwWindow(const ke_window_glfw_params *params)
    : width_(params->width), height_(params->height), title_(params->title), allocator_(params->allocator),
      pipe_api_(params->message_pipe), logger_(params->logger)
{
    void* backend_mem = allocator_->alloc(allocator_, sizeof(RealGlfwBackend), alignof(RealGlfwBackend));
    glfw_ = new (backend_mem) RealGlfwBackend();
    s_glfw_backend = glfw_;
    own_glfw_ = true;

    window_api_.handle = this;
    window_api_.on_initialize = [](ke_window *self) {
        return static_cast<GlfwWindow *>(self->handle)->OnInitialize();
    };
    window_api_.on_shutdown = [](ke_window *self) {
        return static_cast<GlfwWindow *>(self->handle)->OnShutdown();
    };
    window_api_.destroy = [](ke_window *self) {
        if (!self) return;
        auto *win = static_cast<GlfwWindow *>(self->handle);
        auto *alloc = win->allocator_;
        win->~GlfwWindow();
        alloc->free(alloc, win);
    };
    window_api_.should_close = [](ke_window *self) -> ke_bool {
        return static_cast<GlfwWindow *>(self->handle)->ShouldClose();
    };
    window_api_.poll_events = [](ke_window *self) {
        auto *win = static_cast<GlfwWindow *>(self->handle);
        win->glfw_->PollEvents();
        return KE_OK;
    };
    window_api_.get_size = [](ke_window *self, int32_t *w, int32_t *h) {
        return static_cast<GlfwWindow *>(self->handle)->GetSize(w, h);
    };
    window_api_.get_native_handle = [](ke_window *self) {
        return static_cast<GlfwWindow *>(self->handle)->GetNativeHandle();
    };
}

GlfwWindow::~GlfwWindow() {
    if (own_glfw_ && glfw_) {
        glfw_->~GlfwBackend();
        allocator_->free(allocator_, glfw_);
    }
    if (s_glfw_backend == glfw_) {
        s_glfw_backend = nullptr;
    }
}

void GlfwWindow::set_glfw(GlfwBackend* glfw) {
    if (own_glfw_ && glfw_) {
        glfw_->~GlfwBackend();
        allocator_->free(allocator_, glfw_);
    }
    glfw_ = glfw;
    s_glfw_backend = glfw;
    own_glfw_ = false;
}

class GlfwBackend* GlfwWindow::release_glfw() {
    class GlfwBackend* g = glfw_;
    glfw_ = nullptr;
    own_glfw_ = false;
    if (s_glfw_backend == g) s_glfw_backend = nullptr;
    return g;
}

ke_window *GlfwWindow::ToApi() { return &window_api_; }

ke_result GlfwWindow::OnInitialize()
{
    if (glfw_->Init() == 0)
    {
        glfw_log(logger_, KE_LOG_LEVEL_ERROR, "glfwInit() failed");
        return KE_ERROR_WINDOW;
    }
    glfw_->WindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    window_ = glfw_->GlfwCreateWindow(width_, height_, title_.c_str(), nullptr, nullptr);
    if (window_ != nullptr)
    {
        glfw_->SetWindowUserPointer(window_, this);
        glfw_->SetKeyCallback(window_, glfw_key_callback);
        glfw_log(logger_, KE_LOG_LEVEL_INFO, "Window created");
    }
    return (window_ != nullptr) ? KE_OK : KE_ERROR_WINDOW;
}

ke_result GlfwWindow::OnShutdown()
{
    if (window_ != nullptr)
    {
        glfw_log(logger_, KE_LOG_LEVEL_INFO, "Window destroyed");
        glfw_->DestroyWindow(window_);
        glfw_->Terminate();
        window_ = nullptr;
    }
    if (s_glfw_backend == glfw_) s_glfw_backend = nullptr;
    return KE_OK;
}

void *GlfwWindow::GetNativeHandle() const {
#ifdef _WIN32
    return (window_ != nullptr) ? glfw_->GetWin32Window(window_) : nullptr;
#else
    return window_;
#endif
}

ke_result GlfwWindow::GetSize(int32_t *w, int32_t *h) const {
    if (window_) glfw_->GetWindowSize(window_, (int*)w, (int*)h);
    return KE_OK;
}

ke_bool GlfwWindow::ShouldClose() const {
    return (window_ != nullptr) ? (ke_bool)(glfw_->WindowShouldClose(window_) != 0) : (ke_bool)true;
}

} // namespace kernel_engine::window::glfw

extern "C" {
    ke_result ke_window_glfw_create(const ke_window_glfw_params *params, ke_window **out_window) {
        if (!out_window || !params || !params->allocator) return KE_ERROR_INVALID_ARGUMENT;
        void *mem = params->allocator->alloc(params->allocator, sizeof(kernel_engine::window::glfw::GlfwWindow), alignof(kernel_engine::window::glfw::GlfwWindow));
        if (!mem) return KE_ERROR_OUT_OF_MEMORY;
        auto *win = new (mem) kernel_engine::window::glfw::GlfwWindow(params);
        *out_window = win->ToApi();
        return KE_OK;
    }
}
