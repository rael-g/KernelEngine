using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.Logger;
using global::KernelEngine.RenderGraph;

using KernelEngine.Module.Native;
using KernelEngine.Result.Native;

namespace KernelEngine.Render.Webgpu.Native;

public partial struct RenderForwardConfig
{
    public bool IblEnabled;
}
