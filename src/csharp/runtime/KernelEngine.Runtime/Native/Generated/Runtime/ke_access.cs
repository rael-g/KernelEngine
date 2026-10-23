using KernelEngine.Ecs.Native;
using KernelEngine.Logger.Native;
using KernelEngine.Result.Native;
using KernelEngine.Scheduler.Native;

namespace KernelEngine.Runtime.Native;

[NativeTypeName("unsigned int")]
public enum ke_access : uint
{
    KE_ACCESS_READ = 1 << 0,
    KE_ACCESS_WRITE = 1 << 1,
}
