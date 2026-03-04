using System;
using KernelEngine.Core.Native;
using KernelEngine.Core.Allocators;
using KernelEngine.Core.Logging;

namespace KernelEngine.Core.Messaging;

public unsafe class NativeMessagePipe : IDisposable, INativeHandle
{
    private ke_message_pipe* _handle;
    private readonly bool _ownsHandle;
    private readonly IAllocator _allocator;

    IntPtr INativeHandle.Handle => (IntPtr)_handle;

    public NativeMessagePipe(ke_message_pipe* handle, IAllocator allocator, bool ownsHandle = true)
    {
        _handle = handle;
        _allocator = allocator;
        _ownsHandle = ownsHandle;
    }

    public static NativeMessagePipe Create(IAllocator allocator, NativeLogger? logger = null)
    {
        ke_descriptor desc = new ke_descriptor
        {
            allocator = (ke_allocator*)((INativeHandle)allocator).Handle,
            logger = logger != null ? (ke_logger*)((INativeHandle)logger).Handle : null,
            message_pipe = null
        };

        ke_message_pipe* pipe = null;
        var res = NativeMethods.message_pipe_create(&desc, &pipe);
        if (res != ke_result.KE_OK) throw new Exception($"Failed to create native message pipe: {res}");
        
        return new NativeMessagePipe(pipe, allocator, true);
    }

    public ke_result Broadcast<T>(ulong msgId, T data) where T : unmanaged
    {
        if (_handle == null) return ke_result.KE_ERROR;
        return _handle->broadcast(_handle, msgId, &data, (nuint)sizeof(T));
    }

    public bool TryReceive<T>(ulong msgId, out T data) where T : unmanaged
    {
        data = default;
        if (_handle == null) return false;
        
        fixed (T* ptr = &data)
        {
            // Defensive coding: handle both bool and int return types from generator
            var result = _handle->try_receive(_handle, msgId, ptr, (nuint)sizeof(T));
            return Convert.ToBoolean(result);
        }
    }

    public ke_result Pump()
    {
        if (_handle == null) return ke_result.KE_ERROR;
        return _handle->pump(_handle);
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

    ~NativeMessagePipe()
    {
        Dispose();
    }
}
