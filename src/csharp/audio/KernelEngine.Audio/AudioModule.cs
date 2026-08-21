using KernelEngine.Ecs;
using KernelEngine.Runtime;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Audio;

/// <summary>
/// Teaches the scene loader audio's own component vocabulary, so an
/// <c>[entity.components.audio_player]</c> block applies instead of being
/// reported and skipped.
/// </summary>
/// <remarks>
/// Backend-agnostic — it describes the domain's components, not one backend's,
/// so it is added alongside a backend (<c>AddMiniAudio</c>), never instead of one.
/// </remarks>
public sealed unsafe class AudioModule : IRuntimeModule
{
    /// <inheritdoc />
    public string Name => "Audio.Scene";

    /// <inheritdoc />
    public void OnLoad(IRuntime runtime, IServiceProvider services)
    {
        var world = services.GetService<KernelEngine.Framework.World>();
        if (world is null) return;

        var ecs = services.GetRequiredService<INativeEcs>();
        KernelEngine.Audio.Native.NativeMethods.audio_register_scene_apply(
            ((INativeEcs)ecs).Native,
            ((KernelEngine.Framework.INativeWorld)world).Native);
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
