using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Runtime;

public enum RuntimeAccess : uint
{
    Read = 1 << 0,
    Write = 1 << 1,
}
