using System.Numerics;

namespace KernelEngine.Async;

public partial struct AsyncConfig
{
    public uint WorkerCount;
    public uint SubmitCapacity;
}
