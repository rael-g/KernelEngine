using System.Numerics;

using global::KernelEngine.Ecs;
using global::KernelEngine.RenderGraph;

namespace KernelEngine.Render.Frame;

public enum LogLevel : uint
{
    Trace = 0,
    Debug = 1,
    Info = 2,
    Warning = 3,
    Error = 4,
    Critical = 5,
}
