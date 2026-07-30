using KernelEngine.Common.Native;

namespace KernelEngine.Runtime.Native;

[NativeTypeName("unsigned int")]
public enum ke_access : uint
{
    KE_ACCESS_READ = 1 << 0,
    KE_ACCESS_WRITE = 1 << 1,
}
