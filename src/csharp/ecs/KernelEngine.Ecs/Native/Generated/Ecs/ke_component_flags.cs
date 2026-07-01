using KernelEngine.Common.Native;

namespace KernelEngine.Ecs.Native;

public enum ke_component_flags
{
    KE_COMPONENT_NONE = 0,
    KE_COMPONENT_DOUBLE_BUFFERED = 1 << 0,
}
