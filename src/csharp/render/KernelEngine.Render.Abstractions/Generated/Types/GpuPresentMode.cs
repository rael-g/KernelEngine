using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Render;

public enum GpuPresentMode : uint
{
    Fifo = 0,
    Mailbox = 1,
    Immediate = 2,
}
