using KernelEngine.Ecs;
using KernelEngine.Runtime;

using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Audio;

/// <summary>
/// When an <see cref="IAudio"/> is registered, registers the sound component an
/// <c>[entity.sound]</c> block writes and the native system that loads and plays the clip of every
/// sound, with paths relative to the application's base directory.
/// </summary>
public sealed unsafe class AudioModule : IRuntimeModule
{
    private KernelEngine.Audio.Native.ke_sound_module_handle _sound;

    /// <inheritdoc />
    public string Name => "Audio.Scene";

    /// <inheritdoc />
    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var ecs = services.GetRequiredService<INativeEcs>();
        if (services.GetService<Microsoft.Extensions.Logging.ILoggerFactory>() is { } loggerFactory)
            KernelEngine.Audio.Native.NativeMethods.audio_module_set_log_callback(KernelEngine.Logger.NativeLogging.Callback, KernelEngine.Logger.NativeLogging.ContextOf(loggerFactory));
        if (services.GetService<IAudio>() is INativeAudio audio)
            CreateSound(runtime, ecs, audio);
    }

    private void CreateSound(IRuntime runtime, INativeEcs ecs, INativeAudio audio)
    {
        var root = System.Text.Encoding.UTF8.GetBytes(System.AppContext.BaseDirectory + '\0');
        fixed (byte* r = root)
        {
            var config = new KernelEngine.Audio.Native.SoundModuleConfig { Root = (sbyte*)r };
            KernelEngine.Audio.Native.ke_sound_module_handle handle;
            KernelEngine.NativeResults.ThrowIfFailed(KernelEngine.Audio.Native.NativeMethods.sound_module_create(((INativeRuntime)runtime).Native, ecs.Native, audio.Native, &config, &handle), "ke_sound_module_create");
            _sound = handle;
        }
    }

    /// <inheritdoc />
    public void OnUnload(IRuntime runtime, IServiceProvider services)
    {
        if (_sound.@ref == null) return;
        _sound.destroy(_sound.@ref);
        _sound.@ref = null;
    }
}

/// <summary>DI helpers for audio's scene-component registration.</summary>
public static class AudioModuleServiceCollectionExtensions
{
    /// <summary>
    /// Adds the module that makes audio's components addressable from a scene file.
    /// </summary>
    public static IServiceCollection AddAudioScene(this IServiceCollection services)
        => services.Add<IRuntimeModule>(new AudioModule());
}
