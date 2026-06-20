using KernelEngine.Common.Native;

namespace KernelEngine.Runtime.Native;

public enum ke_access
{
    KE_ACCESS_READ = 1 << 0,
    KE_ACCESS_WRITE = 1 << 1,
}
