using KernelEngine.Common.Native;

namespace KernelEngine.Render.Native;

public enum ke_resource_access
{
    KE_ACCESS_NONE = 0,
    KE_ACCESS_SAMPLED = 1,
    KE_ACCESS_COLOR_ATTACHMENT = 2,
    KE_ACCESS_DEPTH_ATTACHMENT = 3,
    KE_ACCESS_STORAGE_READ = 4,
    KE_ACCESS_STORAGE_WRITE = 5,
    KE_ACCESS_STORAGE_RW = 6,
}
