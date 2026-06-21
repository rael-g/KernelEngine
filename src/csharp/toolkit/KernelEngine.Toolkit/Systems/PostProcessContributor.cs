using KernelEngine.Render;


namespace KernelEngine.Framework;

/// <summary>
/// Holds the per-frame post-process state authored by <see cref="PostProcessModule"/>.
/// Mutable so game code can toggle effects at runtime.
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
