using System;
using System.Runtime.InteropServices;
using KernelEngine.Core;
using KernelEngine.Core.Native;
using KernelEngine.Bgfx.Native;
using KernelEngine.Core.Allocators;
using KernelEngine.Core.Logging;
using KernelEngine.Core.Messaging;

namespace KernelEngine.Bgfx;

public unsafe class BgfxRenderSystem : IRenderer, INativeHandle
{
    private ke_system* _systemHandle;
    private ke_render* _renderHandle;
    private readonly IAllocator _allocator;

    IntPtr INativeHandle.Handle => (IntPtr)_systemHandle;

    public BgfxRenderSystem(IAllocator allocator, IWindow window, string shaderPath, NativeLogger? logger = null, NativeMessagePipe? pipe = null)
    {
        _allocator = allocator;
        
        IntPtr pathPtr = Marshal.StringToHGlobalAnsi(shaderPath);
        try
        {
            // ke_system->handle is now the domain object (ke_window/ke_render)
            ke_system* winSysPtr = (ke_system*)((INativeHandle)window).Handle;

            ke_render_bgfx_descriptor desc = new ke_render_bgfx_descriptor
            {
                allocator = (ke_allocator*)((INativeHandle)allocator).Handle,
                logger = logger != null ? (ke_logger*)((INativeHandle)logger).Handle : null,
                message_pipe = pipe != null ? (ke_message_pipe*)((INativeHandle)pipe).Handle : null,
                window = (ke_window*)winSysPtr->handle, // Directly get the API pointer
                shader_path = (sbyte*)pathPtr
            };

            ke_system* system = null;
            var res = KernelEngine.Bgfx.Native.NativeMethods.render_bgfx_create(&desc, &system);
            if (res != ke_result.KE_OK) throw new Exception($"Failed to create BGFX render system: {res}");
            
            _systemHandle = system;
            _renderHandle = (ke_render*)system->handle;
        }
        finally
        {
            Marshal.FreeHGlobal(pathPtr);
        }
    }

    public void ClearColor(float r, float g, float b, float a)
    {
        if (_renderHandle == null) return;
        _renderHandle->clear_color(_renderHandle, r, g, b, a);
    }

    public void Dispose()
    {
        if (_systemHandle != null)
        {
            _systemHandle->destroy(_systemHandle);
            _systemHandle = null;
            _renderHandle = null;
        }
        GC.SuppressFinalize(this);
    }

    ~BgfxRenderSystem()
    {
        Dispose();
    }
}
