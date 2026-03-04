using System;
using KernelEngine.Core.Native;

namespace KernelEngine.Core.Allocators;

public unsafe class NativeAllocator : IAllocator, INativeHandle
{
    private ke_allocator* _handle;
    private readonly bool _ownsHandle;

    IntPtr INativeHandle.Handle => (IntPtr)_handle;

    public NativeAllocator(ke_allocator* handle, bool ownsHandle = true)
    {
        _handle = handle;
        _ownsHandle = ownsHandle;
    }

    public static NativeAllocator CreateMalloc()
    {
        return new NativeAllocator(NativeMethods.allocator_malloc_create(), true);
    }

    public void* Allocate(nuint size, nuint alignment = 0)
    {
        if (_handle == null) throw new ObjectDisposedException(nameof(NativeAllocator));
        return _handle->alloc(_handle, size, alignment);
    }

    public void Free(void* ptr)
    {
        if (_handle == null) return;
        _handle->free(_handle, ptr);
    }

    public void* Reallocate(void* ptr, nuint size)
    {
        if (_handle == null) throw new ObjectDisposedException(nameof(NativeAllocator));
        return _handle->realloc(_handle, ptr, size);
    }

    public void Reset()
    {
        if (_handle == null) return;
        _handle->reset(_handle);
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

    ~NativeAllocator()
    {
        Dispose();
    }
}
