using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework;

/// <summary>
/// Opt-in post-process module — tonemapping, bloom, SSAO.
/// </summary>
public sealed class PostProcessModule : IRuntimeModule
{
    private readonly PostProcessState _seedState;

    public string Name => "PostProcess";

    public IEnumerable<Type> Dependencies => new[] { typeof(SceneRenderModule) };

    public PostProcessModule(
        bool  tonemapping = false, float tonemappingExposure = 1f,  float tonemappingGamma = 2.2f,
        bool  bloom       = false, float bloomThreshold      = 1f,  float bloomIntensity   = 1f,
        bool  ssao        = false, float ssaoRadius          = 0.5f, float ssaoBias        = 0.025f, float ssaoStrength = 1f)
    {
        _seedState = new PostProcessState
        {
            TonemappingEnabled  = tonemapping,
            TonemappingExposure = tonemappingExposure,
            TonemappingGamma    = tonemappingGamma,
            BloomEnabled        = bloom,
            BloomThreshold      = bloomThreshold,
            BloomIntensity      = bloomIntensity,
            SsaoEnabled         = ssao,
            SsaoRadius          = ssaoRadius,
            SsaoBias            = ssaoBias,
            SsaoStrength        = ssaoStrength,
        };
    }

    public void Configure(IServiceCollection services)
    {
        services.AddSingleton(_seedState);
        services.AddSingleton<IFrameContributor, PostProcessContributor>(sp =>
            new PostProcessContributor(sp.GetRequiredService<PostProcessState>()));
    }

    public void OnLoad(IRuntime runtime, IServiceProvider services) { }
}
