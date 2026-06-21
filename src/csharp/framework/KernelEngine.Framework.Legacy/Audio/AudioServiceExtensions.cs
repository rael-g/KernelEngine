
using Microsoft.Extensions.DependencyInjection;
using KernelEngine.Audio;

namespace KernelEngine.Framework.Legacy;

public static class AudioServiceExtensions
{
    /// <summary>
    /// Lifts the registered <see cref="IAudio"/> kernel backend into the framework-shaped
    /// <see cref="IAudioService"/>. Call after the audio backend's DI extension
    /// (e.g. <c>AddMiniAudio()</c>) so the wrapper finds the backend.
    /// </summary>
    public static IServiceCollection AddAudioFramework(this IServiceCollection services)
    {
        services.AddSingleton<IAudioService>(sp => new AudioService(sp.GetRequiredService<IAudio>()));
        return services;
    }
}
