using System.Numerics;
using KernelEngine.Kernel;

namespace KernelEngine.Framework;

/// <summary>
/// Sim-thread ergonomic writer over an <see cref="IFramePacket"/>. Part of the Framework's
/// 3-thread policy: all methods assert they run on <c>ke.sim</c>.
/// </summary>
public sealed class FramePacketSceneWriter : ISceneWriter
{
    private readonly IFramePacket _packet;
    private readonly IKernelFactory _threads;

    public FramePacketSceneWriter(IFramePacket packet, IKernelFactory threads)
    {
        _packet = packet;
        _threads = threads;
    }

    public void ClearColor(float r, float g, float b, float a = 1.0f)
    {
        _threads.AssertCurrentThread("ke.sim");
        _packet.SetClearColor(r, g, b, a);
    }

    public void SetAmbientLight(float r, float g, float b)
    {
        _threads.AssertCurrentThread("ke.sim");
        _packet.SetAmbientLight(r, g, b);
    }

    public void SetCamera(Matrix4x4 view, Matrix4x4 projection, Vector3 position)
    {
        _threads.AssertCurrentThread("ke.sim");
        _packet.SetCamera(view, projection, position);
    }

    public void SetDirectionalLight(Vector3 direction, Vector3 color, float intensity)
    {
        _threads.AssertCurrentThread("ke.sim");
        _packet.SetDirectionalLight(new DirectionalLight
        {
            Direction = direction,
            Color = color,
            Intensity = intensity,
        });
    }

    public void AddDrawCommand(MeshHandle mesh, MaterialHandle material, Matrix4x4 transform)
    {
        _threads.AssertCurrentThread("ke.sim");
        _packet.AddDrawCommand(mesh, material, transform);
    }

    public void SetSkybox(TextureHandle cubemap)
    {
        _threads.AssertCurrentThread("ke.sim");
        _packet.SetSkybox(cubemap);
    }

    public void BeginShadowPass(ShadowMapHandle shadowMap, Matrix4x4 lightView, Matrix4x4 lightProjection)
    {
        _threads.AssertCurrentThread("ke.sim");
        _packet.SetShadow(shadowMap, lightView, lightProjection);
    }

    public void AddShadowDrawCommand(MeshHandle mesh, Matrix4x4 transform)
    {
        _threads.AssertCurrentThread("ke.sim");
        _packet.AddShadowDrawCommand(mesh, transform);
    }

    public void EndShadowPass()
    {
        _threads.AssertCurrentThread("ke.sim");
    }

    public void SetShadowMap(ShadowMapHandle shadowMap)
    {
        _threads.AssertCurrentThread("ke.sim");
        _packet.SetActiveShadowMap(shadowMap);
    }

    public void SetSsao(bool enabled, float radius = 0.5f, float bias = 0.025f, float strength = 1.0f)
    {
        _threads.AssertCurrentThread("ke.sim");
        _packet.SetSsao(enabled, radius, bias, strength);
    }

    public void SetTonemapping(bool enabled, float exposure = 1.0f, float gamma = 2.2f)
    {
        _threads.AssertCurrentThread("ke.sim");
        _packet.SetTonemapping(enabled, exposure, gamma);
    }

    public void SetBloom(bool enabled, float threshold = 1.0f, float intensity = 0.5f)
    {
        _threads.AssertCurrentThread("ke.sim");
        _packet.SetBloom(enabled, threshold, intensity);
    }
}
