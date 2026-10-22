using KernelEngine.Audio.MiniAudio.Native;
using KernelEngine.Common.Native;
using KernelEngine.Logger;

using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Audio.MiniAudio;

public static class ServiceCollectionExtensions
{
    /// <summary>
    /// Registers a miniaudio-backed <see cref="IAudio"/> singleton and the audio
    /// domain's own node types, so a scene naming <c>AudioPlayer</c> resolves without
    /// each game repeating the registration. The library logs to the registered
    /// <see cref="ILogger"/>, or to stderr when there is none.
    /// </summary>
    public static IServiceCollection AddMiniAudio(this IServiceCollection services)
    {
        services.AddSingleton<IAudio>(sp =>
        {
            unsafe
            {
                if (sp.GetService<ILogger>() is { } logger)
                    KernelEngine.Audio.MiniAudio.Native.NativeMethods.audio_miniaudio_set_log_callback(LogCallbackNative.Pointer, LogCallbackNative.Pin(logger.Log));

                ke_error* err = null;
                var handle = KernelEngine.Audio.MiniAudio.Native.NativeMethods.audio_miniaudio_create(&err);
                if (handle.@ref == null) throw NativeErrors.FromNative(err, "audio_miniaudio_create");
                return new KernelEngine.Audio.Audio(handle);
            }
        });
        KernelEngine.Framework.AudioComponentsNodeTypes.AddAudioComponentsNodeTypes(services);
        services.AddAudioScene();
        return services;
    }
}
