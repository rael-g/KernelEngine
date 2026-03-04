using System;

namespace KernelEngine.Core.Allocators;

public interface IAllocator : IDisposable
{
    unsafe void* Allocate(nuint size, nuint alignment = 0);
    unsafe void Free(void* ptr);
    unsafe void* Reallocate(void* ptr, nuint size);
    void Reset();
}
