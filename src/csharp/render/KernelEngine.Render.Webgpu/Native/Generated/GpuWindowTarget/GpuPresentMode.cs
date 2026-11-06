using System.Numerics;

using KernelEngine.Render.Native;
using KernelEngine.Result.Native;
using KernelEngine.Window.Native;

namespace KernelEngine.Render.Webgpu.Native;

[NativeTypeName("unsigned int")]
public enum GpuPresentMode : uint
{
    Fifo = 0,
    Mailbox = 1,
    Immediate = 2,
}
