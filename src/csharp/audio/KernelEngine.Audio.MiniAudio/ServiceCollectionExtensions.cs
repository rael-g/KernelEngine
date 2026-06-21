using KernelEngine.Audio.MiniAudio.Native;
using KernelEngine.Common.Native;
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Logger;

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
                var logger = sp.GetService<INativeLogger>();
                var @params = new ke_audio_miniaudio_params
                {
                    logger = logger != null ? logger.Native : null,
                };

                ke_error* err = null;
                var handle = KernelEngine.Audio.MiniAudio.Native.NativeMethods.audio_miniaudio_create(&@params, &err);
                if (handle.@ref == null) throw KernelError.FromNative(err, "audio_miniaudio_create");
                return new KernelEngine.Audio.Audio(handle);
            }
        });
        return services;
    }
}
