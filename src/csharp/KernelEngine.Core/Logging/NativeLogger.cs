using System;
using System.Runtime.InteropServices;
using KernelEngine.Core.Native;
using KernelEngine.Core.Allocators;

namespace KernelEngine.Core.Logging;

public unsafe class NativeLogger : IDisposable, INativeHandle
{
    private ke_logger* _handle;
    private readonly bool _ownsHandle;
    private readonly IAllocator _allocator;

    IntPtr INativeHandle.Handle => (IntPtr)_handle;

    public NativeLogger(ke_logger* handle, IAllocator allocator, bool ownsHandle = true)
    {
        _handle = handle;
        _allocator = allocator;
        _ownsHandle = ownsHandle;
    }

    public static NativeLogger Create(IAllocator allocator)
    {
        ke_descriptor desc = new ke_descriptor
        {
            allocator = (ke_allocator*)((INativeHandle)allocator).Handle,
            logger = null,
            message_pipe = null
        };

        ke_logger* logger = null;
        var res = NativeMethods.logger_create(&desc, &logger);
        if (res != ke_result.KE_OK) throw new Exception($"Failed to create native logger: {res}");
        
        return new NativeLogger(logger, allocator, true);
    }

    public void Log(ke_log_level level, string tag, string message)
    {
        if (_handle == null) return;

        IntPtr tagPtr = Marshal.StringToHGlobalAnsi(tag);
        IntPtr msgPtr = Marshal.StringToHGlobalAnsi(message);

        try
        {
            ke_log_event ev = new ke_log_event
            {
                level = (int)level,
                tag = (sbyte*)tagPtr,
                message = (sbyte*)msgPtr
            };
            _handle->log(_handle, &ev);
        }
        finally
        {
            Marshal.FreeHGlobal(tagPtr);
            Marshal.FreeHGlobal(msgPtr);
        }
    }

    public void AddSink(ke_logger_sink sink)
    {
        if (_handle == null) return;
        _handle->add_sink(_handle, sink);
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

    ~NativeLogger()
    {
        Dispose();
    }
}
