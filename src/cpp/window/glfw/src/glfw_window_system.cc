#include <kernel_engine/window/glfw/glfw_window_system.hh>
#include <kernel_engine/kernel/context/allocator.h>
#include <kernel_engine/kernel/input/input_messages.h>
#include <kernel_engine/kernel/logger/logger.h>
#include <new>

#define GLFW_EXPOSE_NATIVE_WIN32
#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>

namespace kernel_engine::window::glfw
{

static void glfw_key_callback(GLFWwindow *window, int key, int scancode, int action, int mods)
{
    (void)scancode;
    (void)mods;
    auto *sys = static_cast<GlfwWindowSystem *>(glfwGetWindowUserPointer(window));
    if ((sys != nullptr) && (sys->GetPipe() != nullptr))
    {
        ke_msg_key_event msg = {key, action};
        sys->GetPipe()->broadcast(sys->GetPipe(), KE_MSG_KEY_EVENT, &msg, sizeof(msg));
    }
}

GlfwWindowSystem::GlfwWindowSystem(const ke_window_glfw_descriptor *desc)
    : width_(desc->width), height_(desc->height), title_(desc->title), allocator_(desc->allocator),
      pipe_api_(desc->message_pipe), logger_(desc->logger)
{
    window_api_.handle = this;
    window_api_.on_initialize = [](ke_window *self) {
        return static_cast<GlfwWindowSystem *>(self->handle)->OnInitialize();
    };
    window_api_.on_shutdown = [](ke_window *self) {
        return static_cast<GlfwWindowSystem *>(self->handle)->OnShutdown();
    };
    window_api_.destroy = [](ke_window *self) {
        auto *sys = static_cast<GlfwWindowSystem *>(self->handle);
        auto *alloc = sys->allocator_;
        sys->~GlfwWindowSystem();
        alloc->free(alloc, sys);
    };
    window_api_.should_close = [](ke_window *self) {
        return static_cast<GlfwWindowSystem *>(self->handle)->ShouldClose();
    };
    window_api_.poll_events = [](ke_window *self) {
        (void)self;
        glfwPollEvents();
        return KE_OK;
    };
    window_api_.get_size = [](ke_window *self, int *w, int *h) {
        return static_cast<GlfwWindowSystem *>(self->handle)->GetSize(w, h);
    };
    window_api_.get_native_handle = [](ke_window *self) {
        return static_cast<GlfwWindowSystem *>(self->handle)->GetNativeHandle();
    };
}

GlfwWindowSystem::~GlfwWindowSystem() {}
ke_window *GlfwWindowSystem::ToApi() { return &window_api_; }

static void glfw_log(ke_logger *logger, ke_log_level level, const char *msg)
{
    if (!logger || level < logger->runtime_limit) return;
    ke_log_event ev = {(int)level, "glfw", msg};
    logger->log(logger, &ev);
}

ke_result GlfwWindowSystem::OnInitialize()
{
    if (glfwInit() == 0)
    {
        glfw_log(logger_, KE_LOG_LEVEL_ERROR, "glfwInit() failed");
        return KE_ERROR_WINDOW;
    }
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    window_ = glfwCreateWindow(width_, height_, title_.c_str(), nullptr, nullptr);
    if (window_ != nullptr)
    {
        glfwSetWindowUserPointer(window_, this);
        glfwSetKeyCallback(window_, glfw_key_callback);
        glfw_log(logger_, KE_LOG_LEVEL_INFO, "Window created");
    }
    return (window_ != nullptr) ? KE_OK : KE_ERROR_WINDOW;
}

ke_result GlfwWindowSystem::OnShutdown()
{
    if (window_ != nullptr)
    {
        glfw_log(logger_, KE_LOG_LEVEL_INFO, "Window destroyed");
        glfwDestroyWindow(window_);
        glfwTerminate();
    }
    return KE_OK;
}

void *GlfwWindowSystem::GetNativeHandle() const {
#ifdef _WIN32
    return (window_ != nullptr) ? (void *)(uintptr_t)glfwGetWin32Window(window_) : nullptr;
#else
    return window_;
#endif
}

ke_result GlfwWindowSystem::GetSize(int *w, int *h) const {
    if (window_) glfwGetWindowSize(window_, w, h);
    return KE_OK;
}

bool GlfwWindowSystem::ShouldClose() const {
    return (window_ != nullptr) ? (glfwWindowShouldClose(window_) != 0) : true;
}

} // namespace kernel_engine::window::glfw

extern "C" {
    ke_result ke_window_glfw_create(const ke_window_glfw_descriptor *desc, ke_window **out_window) {
        if (!out_window || !desc || !desc->allocator) return KE_ERROR_INVALID_ARGUMENT;
        void *mem = desc->allocator->alloc(desc->allocator, sizeof(kernel_engine::window::glfw::GlfwWindowSystem), 0);
        auto *sys = new (mem) kernel_engine::window::glfw::GlfwWindowSystem(desc);
        *out_window = sys->ToApi();
        return KE_OK;
    }
}
