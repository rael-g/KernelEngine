using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Holds the per-frame post-process state authored by <see cref="PostProcessModule"/>.
/// The contributor reads from this each frame and writes to the packet; the
/// holder is mutable so game code (or future post-process nodes) can flip
/// effects on/off at runtime without restarting the module.
/// </summary>
public sealed class PostProcessState
{
    public bool  TonemappingEnabled;
    public float TonemappingExposure = 1f;
    public float TonemappingGamma    = 2.2f;

    public bool  BloomEnabled;
    public float BloomThreshold = 1f;
    public float BloomIntensity = 1f;

    public bool  SsaoEnabled;
    public float SsaoRadius   = 0.5f;
    public float SsaoBias     = 0.025f;
    public float SsaoStrength = 1f;
}

/// <summary>
/// Per-frame: pushes the post-process state (tonemap, bloom, SSAO) into the
/// packet. The renderer reads the packet flags every frame, so these MUST be
/// written each tick or the renderer reverts to "all post-FX disabled".
/// </summary>
internal sealed class PostProcessContributor : IFrameContributor
{
    private readonly PostProcessState _state;

    public PostProcessContributor(PostProcessState state) => _state = state;

    public void Contribute(IFramePacket packet)
    {
        packet.SetTonemapping(_state.TonemappingEnabled, _state.TonemappingExposure, _state.TonemappingGamma);
        packet.SetBloom(_state.BloomEnabled, _state.BloomThreshold, _state.BloomIntensity);
        packet.SetSsao(_state.SsaoEnabled, _state.SsaoRadius, _state.SsaoBias, _state.SsaoStrength);
    }
}
