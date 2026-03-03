#include "GlfwWindowSystem.hh"
#include <cstdio>
#include <kernel_engine/core/common/hash.h>
#include <kernel_engine/core/context/allocator.h>
#include <kernel_engine/core/input/input_messages.h>
#include <new>

#define GLFW_EXPOSE_NATIVE_WIN32
#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>

namespace kernel_engine::domain::window
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
    window_api_.destroy = [](ke_window *self) { (void)self; };
    window_api_.should_close = [](ke_window *self) {
        return static_cast<GlfwWindowSystem *>(self->handle)->ShouldClose();
    };
    window_api_.poll_events = [](ke_window * /*self*/) {
        return kernel_engine::domain::window::GlfwWindowSystem::PollEvents();
    };
    window_api_.swap_buffers = [](ke_window * /*self*/) {
        return kernel_engine::domain::window::GlfwWindowSystem::SwapBuffers();
    };
    window_api_.get_size = [](ke_window *self, int *w, int *h) {
        return static_cast<GlfwWindowSystem *>(self->handle)->GetSize(w, h);
    };
    window_api_.get_native_handle = [](ke_window *self) {
        return static_cast<GlfwWindowSystem *>(self->handle)->GetNativeHandle();
    };

    engine_api_.handle = this;
    engine_api_.numeric_id = ke_hash_string("ke_window_glfw");
    engine_api_.destroy = [](ke_system *self) {
        auto *sys = static_cast<GlfwWindowSystem *>(self->handle);
        auto *alloc = sys->allocator_;
        if (alloc)
        {
            sys->~GlfwWindowSystem();
            alloc->free(alloc, sys);
        }
    };
    engine_api_.on_initialize = [](ke_system *self) {
        return static_cast<GlfwWindowSystem *>(self->handle)->OnInitialize();
    };
    engine_api_.on_shutdown = [](ke_system *self) {
        return static_cast<GlfwWindowSystem *>(self->handle)->OnShutdown();
    };
    engine_api_.on_update = [](ke_system * /*self*/, const ke_frame *frame) {
        if (frame)
        {
            return kernel_engine::domain::window::GlfwWindowSystem::OnUpdate(*frame);
        }
        ke_frame dummy = {0, 0.0, 0.0};
        return kernel_engine::domain::window::GlfwWindowSystem::OnUpdate(dummy);
    };
}

GlfwWindowSystem::~GlfwWindowSystem() = default;

uint64_t GlfwWindowSystem::Id() const
{
    return engine_api_.numeric_id;
}
ke_system *GlfwWindowSystem::ToApi()
{
    return &engine_api_;
}

ke_result GlfwWindowSystem::OnInitialize()
{
    if (glfwInit() == 0)
    {
        if (logger_ != nullptr)
        {
            logger_->log(logger_, KE_LOG_LEVEL_ERROR, "window", "Failed to initialize GLFW.");
        }
        return KE_ERROR_WINDOW;
    }
    glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);
    window_ = glfwCreateWindow(width_, height_, title_.c_str(), nullptr, nullptr);
    if (window_ != nullptr)
    {
        glfwSetWindowUserPointer(window_, this);
        glfwSetKeyCallback(window_, glfw_key_callback);
        if (logger_ != nullptr)
        {
            char buf[256];
            snprintf(buf, sizeof(buf), "Window created: %dx%d", width_, height_);
            logger_->log(logger_, KE_LOG_LEVEL_INFO, "window", buf);
        }
    }
    else
    {
        if (logger_ != nullptr)
        {
            logger_->log(logger_, KE_LOG_LEVEL_ERROR, "window", "Failed to create window.");
        }
        glfwTerminate();
        return KE_ERROR_WINDOW;
    }
    return KE_OK;
}

ke_result GlfwWindowSystem::OnShutdown()
{
    if (window_ != nullptr)
    {
        glfwDestroyWindow(window_);
        window_ = nullptr;
        glfwTerminate();
        if (logger_ != nullptr)
        {
            logger_->log(logger_, KE_LOG_LEVEL_DEBUG, "window", "GlfwWindowSystem shutdown.");
        }
    }
    return KE_OK;
}

ke_result GlfwWindowSystem::OnUpdate(const ke_frame &frame)
{
    (void)frame;
    glfwPollEvents();
    return KE_OK;
}
bool GlfwWindowSystem::ShouldClose() const
{
    return ((window_ != nullptr) ? glfwWindowShouldClose(window_) : 1) != 0;
}
ke_result GlfwWindowSystem::PollEvents()
{
    glfwPollEvents();
    return KE_OK;
}
ke_result GlfwWindowSystem::SwapBuffers()
{
    return KE_OK;
}
ke_result GlfwWindowSystem::GetSize(int *w, int *h) const
{
    if (window_ != nullptr)
    {
        glfwGetWindowSize(window_, w, h);
    }
    return KE_OK;
}
int GlfwWindowSystem::GetWidth() const
{
    int w = 0;
    int h = 0;
    GetSize(&w, &h);
    return w;
}
int GlfwWindowSystem::GetHeight() const
{
    int w = 0;
    int h = 0;
    GetSize(&w, &h);
    return h;
}

void *GlfwWindowSystem::GetNativeHandle() const
{
#ifdef _WIN32
    return (window_ != nullptr) ? (void *)(uintptr_t)glfwGetWin32Window(window_) : nullptr;
#else
    return window_;
#endif
}

} // namespace kernel_engine::domain::window

extern "C"
{

    ke_result ke_window_glfw_create(const ke_window_glfw_descriptor *desc, ke_system **out_system)
    {
        if (out_system == nullptr)
        {
            return KE_ERROR_INVALID_ARGUMENT;
        }
        *out_system = NULL;

        if ((desc == nullptr) || (desc->allocator == nullptr))
        {
            return KE_ERROR_INVALID_ARGUMENT;
        }
        using namespace kernel_engine::domain::window;
        ke_allocator *alloc = desc->allocator;

        void *mem = alloc->alloc(alloc, sizeof(GlfwWindowSystem), 0);
        if (mem == nullptr)
        {
            return KE_ERROR_OUT_OF_MEMORY;
        }

        GlfwWindowSystem *sys = new (mem) GlfwWindowSystem(desc);
        *out_system = sys->ToApi();
        return KE_OK;
    }
}
