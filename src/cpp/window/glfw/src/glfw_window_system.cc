#include <kernel_engine/window/glfw/glfw_window_system.hh>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/input/input_messages.h>
#include <kernel_engine/kernel/logger/logger.h>
#include <new>
#include <cstring>

#define GLFW_EXPOSE_NATIVE_WIN32
#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>

#include "glfw_interface.hh"

namespace kernel_engine::window::glfw
{

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
    auto *sys = static_cast<GlfwWindowSystem *>(s_glfw_backend->GetWindowUserPointer(window));
    if ((sys != nullptr) && (sys->GetPipe() != nullptr))
    {
        ke_msg_key_event msg = {(int32_t)key, (int32_t)action};
        sys->GetPipe()->broadcast(sys->GetPipe(), KE_MSG_KEY_EVENT, &msg, sizeof(msg));
    }
}

GlfwWindowSystem::GlfwWindowSystem(const ke_window_glfw_params *params)
    : width_(params->width), height_(params->height), title_(params->title), allocator_(params->allocator),
      pipe_api_(params->message_pipe), logger_(params->logger)
{
    void* backend_mem = allocator_->alloc(allocator_, sizeof(RealGlfwBackend), 0);
    glfw_ = new (backend_mem) RealGlfwBackend();
    s_glfw_backend = glfw_;
    own_glfw_ = true;

    window_api_.handle = this;
    window_api_.on_initialize = [](ke_window *self) {
        return static_cast<GlfwWindowSystem *>(self->handle)->OnInitialize();
    };
    window_api_.on_shutdown = [](ke_window *self) {
        return static_cast<GlfwWindowSystem *>(self->handle)->OnShutdown();
    };
    window_api_.destroy = [](ke_window *self) {
        if (!self) return;
        auto *sys = static_cast<GlfwWindowSystem *>(self->handle);
        auto *alloc = sys->allocator_;
        sys->~GlfwWindowSystem();
        alloc->free(alloc, sys);
    };
    window_api_.should_close = [](ke_window *self) -> ke_bool {
        return static_cast<GlfwWindowSystem *>(self->handle)->ShouldClose();
    };
    window_api_.poll_events = [](ke_window *self) {
        auto *sys = static_cast<GlfwWindowSystem *>(self->handle);
        sys->glfw_->PollEvents();
        return KE_OK;
    };
    window_api_.get_size = [](ke_window *self, int32_t *w, int32_t *h) {
        return static_cast<GlfwWindowSystem *>(self->handle)->GetSize(w, h);
    };
    window_api_.get_native_handle = [](ke_window *self) {
        return static_cast<GlfwWindowSystem *>(self->handle)->GetNativeHandle();
    };
}

GlfwWindowSystem::~GlfwWindowSystem() {
    if (own_glfw_ && glfw_) {
        glfw_->~GlfwBackend();
        allocator_->free(allocator_, glfw_);
    }
    if (s_glfw_backend == glfw_) {
        s_glfw_backend = nullptr;
    }
}

void GlfwWindowSystem::set_glfw(GlfwBackend* glfw) {
    if (own_glfw_ && glfw_) {
        glfw_->~GlfwBackend();
        allocator_->free(allocator_, glfw_);
    }
    glfw_ = glfw;
    s_glfw_backend = glfw;
    own_glfw_ = false;
}

ke_window *GlfwWindowSystem::ToApi() { return &window_api_; }

static void glfw_log(ke_logger *logger, ke_log_level level, const char *msg)
{
    if (!logger || (int32_t)level < logger->runtime_limit) return;
    ke_log_event ev = {(int32_t)level, "glfw", msg};
    logger->log(logger, &ev);
}

ke_result GlfwWindowSystem::OnInitialize()
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

ke_result GlfwWindowSystem::OnShutdown()
{
    if (window_ != nullptr)
    {
        glfw_log(logger_, KE_LOG_LEVEL_INFO, "Window destroyed");
        glfw_->DestroyWindow(window_);
        glfw_->Terminate();
        window_ = nullptr;
    }
    return KE_OK;
}

void *GlfwWindowSystem::GetNativeHandle() const {
#ifdef _WIN32
    return (window_ != nullptr) ? glfw_->GetWin32Window(window_) : nullptr;
#else
    return window_;
#endif
}

ke_result GlfwWindowSystem::GetSize(int32_t *w, int32_t *h) const {
    if (window_) glfw_->GetWindowSize(window_, (int*)w, (int*)h);
    return KE_OK;
}

ke_bool GlfwWindowSystem::ShouldClose() const {
    return (window_ != nullptr) ? (ke_bool)(glfw_->WindowShouldClose(window_) != 0) : (ke_bool)true;
}

} // namespace kernel_engine::window::glfw

extern "C" {
    ke_result ke_window_glfw_create(const ke_window_glfw_params *params, ke_window **out_window) {
        if (!out_window || !params || !params->allocator) return KE_ERROR_INVALID_ARGUMENT;
        void *mem = params->allocator->alloc(params->allocator, sizeof(kernel_engine::window::glfw::GlfwWindowSystem), 0);
        auto *sys = new (mem) kernel_engine::window::glfw::GlfwWindowSystem(params);
        *out_window = sys->ToApi();
        return KE_OK;
    }
}
