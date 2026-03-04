using KernelEngine.Core.Native;
using KernelEngine.Core.Allocators;
using KernelEngine.Core.Logging;
using KernelEngine.Core.Messaging;

namespace KernelEngine.Core;

public unsafe class Engine : IDisposable, INativeHandle
{
    private ke_engine* _handle;
    private readonly bool _ownsHandle;
    private readonly IAllocator _allocator;

    // Explicit implementation hides this from Program.cs
    IntPtr INativeHandle.Handle => (IntPtr)_handle;

    private Engine(ke_engine* handle, IAllocator allocator, bool ownsHandle = true)
    {
        _handle = handle;
        _allocator = allocator;
        _ownsHandle = ownsHandle;
    }

    public static Engine Create(IAllocator allocator, NativeLogger? logger = null, NativeMessagePipe? pipe = null)
    {
        ke_descriptor desc = new ke_descriptor
        {
            allocator = (ke_allocator*)((INativeHandle)allocator).Handle,
            logger = logger != null ? (ke_logger*)((INativeHandle)logger).Handle : null,
            message_pipe = pipe != null ? (ke_message_pipe*)((INativeHandle)pipe).Handle : null
        };

        ke_engine* engine = null;
        var res = NativeMethods.engine_create(&desc, &engine);
        if (res != ke_result.KE_OK) throw new Exception($"Failed to create native engine: {res}");
        
        return new Engine(engine, allocator, true);
    }

    public ke_result Initialize()
    {
        if (_handle == null) return ke_result.KE_ERROR;
        return _handle->initialize(_handle);
    }

    public ke_result Tick()
    {
        if (_handle == null) return ke_result.KE_ERROR;
        return _handle->tick(_handle, null);
    }

    public ke_result Shutdown()
    {
        if (_handle == null) return ke_result.KE_OK;
        return _handle->shutdown(_handle);
    }

    public ke_result RegisterSystem(ISystem system)
    {
        if (_handle == null) return ke_result.KE_ERROR;
        return _handle->register_system(_handle, (ke_system*)((INativeHandle)system).Handle);
    }

    public void Dispose()
    {
        if (_handle != null)
        {
            if (_ownsHandle)
            {
                _handle->destroy(_handle);
            }
            _handle = null;
        }
        GC.SuppressFinalize(this);
    }

    ~Engine()
    {
        Dispose();
    }
}
