using KernelEngine.Common.Native;

namespace KernelEngine.Runtime.Native;

public enum ke_phase
{
    KE_PHASE_STARTUP = 0,
    KE_PHASE_PRE_UPDATE = 1,
    KE_PHASE_FIXED_UPDATE = 2,
    KE_PHASE_UPDATE = 3,
    KE_PHASE_POST_UPDATE = 4,
    KE_PHASE_SHUTDOWN = 5,
}
