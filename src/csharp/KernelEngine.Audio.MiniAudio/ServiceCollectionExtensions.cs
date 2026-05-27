using KernelEngine.Audio.MiniAudio.Native;
using KernelEngine.Kernel;
using KernelEngine.Kernel.Native;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Audio.MiniAudio;

public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers a miniaudio-backed <see cref="IAudio"/> singleton.
    /// Requires <c>AddKernel()</c> to be called first.
    /// </summary>
    public static IServiceCollection AddMiniAudio(this IServiceCollection services)
    {
        services.AddSingleton<IAudio>(sp =>
        {
            unsafe
            {
                var logger = sp.GetService<Logger>();
                var @params = new ke_audio_miniaudio_params
                {
                    allocator = sp.GetRequiredService<Allocator>().Native,
                    logger    = logger != null ? logger.Native : null,
                };

                ke_audio* native;
                KernelException.ThrowIfFailed(
                    KernelEngine.Audio.MiniAudio.Native.NativeMethods.audio_miniaudio_create(&@params, &native).ToManaged());
                return new KernelEngine.Kernel.Audio(native);
            }
        });
        return services;
    }
}
