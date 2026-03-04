using System;
using System.Runtime.InteropServices;
using System.ComponentModel;
using KernelEngine.Core;
using KernelEngine.Core.Native;
using KernelEngine.Glfw.Native;
using KernelEngine.Core.Allocators;
using KernelEngine.Core.Logging;
using KernelEngine.Core.Messaging;

namespace KernelEngine.Glfw;

public unsafe class GlfwWindowSystem : IWindow, INativeHandle
{
    private ke_system* _systemHandle;
    private ke_window* _windowHandle;
    private readonly IAllocator _allocator;

    IntPtr INativeHandle.Handle => (IntPtr)_systemHandle;

    /// @brief Internal pointer to the native window domain object.
    [EditorBrowsable(EditorBrowsableState.Never)]
    public ke_window* NativeWindow => _windowHandle;

    public GlfwWindowSystem(IAllocator allocator, int width, int height, string title, NativeLogger? logger = null, NativeMessagePipe? pipe = null)
    {
        _allocator = allocator;
        
        IntPtr titlePtr = Marshal.StringToHGlobalAnsi(title);
        try
        {
            ke_window_glfw_descriptor desc = new ke_window_glfw_descriptor
            {
                allocator = (ke_allocator*)((INativeHandle)allocator).Handle,
                logger = logger != null ? (ke_logger*)((INativeHandle)logger).Handle : null,
                message_pipe = pipe != null ? (ke_message_pipe*)((INativeHandle)pipe).Handle : null,
                width = width,
                height = height,
                title = (sbyte*)titlePtr
            };

            ke_system* system = null;
            var res = KernelEngine.Glfw.Native.NativeMethods.window_glfw_create(&desc, &system);
            if (res != ke_result.KE_OK) throw new Exception($"Failed to create GLFW window system: {res}");
            
            _systemHandle = system;
            _windowHandle = (ke_window*)system->handle;

            if (_windowHandle == null) throw new Exception("Native window handle is NULL after creation.");
        }
        finally
        {
            Marshal.FreeHGlobal(titlePtr);
        }
    }

    public bool ShouldClose()
    {
        if (_windowHandle == null) return true;
        // Defensive: Handle both bool and int from generator
        var result = _windowHandle->should_close(_windowHandle);
        return Convert.ToBoolean(result);
    }

    public void PollEvents()
    {
        if (_windowHandle == null) return;
        _windowHandle->poll_events(_windowHandle);
    }

    public void Dispose()
    {
        if (_systemHandle != null)
        {
            _systemHandle->destroy(_systemHandle);
            _systemHandle = null;
            _windowHandle = null;
        }
        GC.SuppressFinalize(this);
    }

    ~GlfwWindowSystem()
    {
        Dispose();
    }
}
