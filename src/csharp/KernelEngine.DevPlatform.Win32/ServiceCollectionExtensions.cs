using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using Microsoft.Extensions.DependencyInjection;

using DevPlatformWrapper = KernelEngine.Kernel.DevPlatform;
using Win32Native        = KernelEngine.DevPlatform.Win32.Native.NativeMethods;

namespace KernelEngine.DevPlatform.Win32;

public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers a Win32-backed <see cref="DevPlatform"/> singleton.
    /// Adds OS thread naming (visible in debuggers and profilers) and, in future revisions,
    /// SEH crash handler installation and minidump writing.
    ///
    /// Intended for development builds. Skip in shipped builds for restricted platforms.
    /// </summary>
    public static IServiceCollection AddWin32DevPlatform(this IServiceCollection services)
    {
        services.AddSingleton<DevPlatformWrapper>(sp =>
        {
            unsafe
            {
                var alloc = sp.GetRequiredService<Allocator>();
                ke_dev_platform* native;
                var res = Win32Native.dev_platform_create_win32(alloc.Native, &native);
                KernelException.ThrowIfFailed(res, nameof(Win32Native.dev_platform_create_win32));
                return new DevPlatformWrapper(native);
            }
        });
        return services;
    }
}
