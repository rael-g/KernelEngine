using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Runtime;

public enum RuntimePhase : uint
{
    Startup = 0,
    PreUpdate = 1,
    FixedPreUpdate = 2,
    FixedUpdate = 3,
    FixedPostUpdate = 4,
    Update = 5,
    PostUpdate = 6,
    Render = 7,
    Shutdown = 8,
}
