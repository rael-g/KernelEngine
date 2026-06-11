using System.Numerics;
using KernelEngine.Kernel;
using Microsoft.Extensions.DependencyInjection;

namespace KernelEngine.Framework;

/// <summary>
/// Contributes a single directional light + ambient color to every frame packet.
/// First port from .Legacy DirectionalLight node — multi-light (point/spot)
/// support lands as later examples need it.
/// </summary>
public sealed class LightModule : IRuntimeModule, IFrameContributor
{
    public Vector3 Direction { get; init; } = new(0.2f, 1f, 0.5f);
    public Vector3 Color     { get; init; } = Vector3.One;
    public float   Intensity { get; init; } = 1f;
    public Vector3 Ambient   { get; init; } = new(0.2f, 0.2f, 0.2f);

    public string Name => "Light";

    public void Configure(IServiceCollection services) => services.AddSingleton<IFrameContributor>(this);

    public void OnLoad(IRuntime runtime, IServiceProvider services) { /* no-op */ }

    public void Contribute(IFramePacket packet)
    {
        packet.SetAmbientLight(Ambient.X, Ambient.Y, Ambient.Z);
        packet.SetDirectionalLight(new DirectionalLightData
        {
            Direction = Vector3.Normalize(Direction),
            Color     = Color,
            Intensity = Intensity,
        });
    }
}
