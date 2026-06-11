using System.Numerics;
using KernelEngine.Kernel;

namespace Pong;

/// <summary>
/// Shared materials + audio handles for the Pong scene. Built once at the
/// start of the scene load and injected into the scripts that need them via
/// DI. Construction touches the renderer + audio device — the DI factory MUST
/// run on the render worker (which is true today because the SceneModule
/// callback dispatches itself there).
/// </summary>
public sealed class PongResources
{
    public MaterialHandle WhiteMat   { get; }
    public MaterialHandle WallMat    { get; }
    public SoundHandle    HitSound   { get; }
    public SoundHandle    ScoreSound { get; }

    public PongResources(IRenderer renderer, IAudio audio)
    {
        WhiteMat = renderer.CreateMaterial(new Vector4(0.95f, 0.95f, 0.95f, 1f), roughness: 1f).Value;
        WallMat  = renderer.CreateMaterial(new Vector4(0.15f, 0.15f, 0.20f, 1f), roughness: 1f).Value;

        var assetsDir = Path.Combine(AppContext.BaseDirectory, "assets", "sounds");
        HitSound      = audio.LoadSound(Path.Combine(assetsDir, "hit.wav"));
        ScoreSound    = audio.LoadSound(Path.Combine(assetsDir, "score.wav"));
    }
}
