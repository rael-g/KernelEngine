using System.Numerics;
using KernelEngine.Kernel.Native;

namespace KernelEngine.Kernel;

public sealed unsafe class FramePacketSceneWriter : ISceneWriter
{
    private readonly FramePacket _packet;

    public FramePacketSceneWriter(FramePacket packet)
    {
        _packet = packet;
    }

    public void ClearColor(float r, float g, float b, float a = 1.0f)
    {
        KernelThread.AssertCurrent("ke.sim");
        _packet.SetClearColor(r, g, b, a);
    }

    public void SetAmbientLight(float r, float g, float b)
    {
        KernelThread.AssertCurrent("ke.sim");
        _packet.SetAmbientLight(r, g, b);
    }

    public void SetCamera(Matrix4x4 view, Matrix4x4 projection, Vector3 position)
    {
        KernelThread.AssertCurrent("ke.sim");
        _packet.SetCamera(view, projection, position);
    }

    public void SetDirectionalLight(Vector3 direction, Vector3 color, float intensity)
    {
        KernelThread.AssertCurrent("ke.sim");
        _packet.SetDirectionalLight(new DirectionalLight
        {
            Direction = direction,
            Color = color,
            Intensity = intensity,
        });
    }

    public void AddDrawCommand(MeshHandle mesh, MaterialHandle material, Matrix4x4 transform)
    {
        KernelThread.AssertCurrent("ke.sim");
        _packet.AddDrawCommand(mesh, material, transform);
    }

    public void SetSkybox(TextureHandle cubemap)
    {
        KernelThread.AssertCurrent("ke.sim");
        _packet.SetSkybox(cubemap);
    }

    public void BeginShadowPass(ShadowMapHandle shadowMap, Matrix4x4 lightView, Matrix4x4 lightProjection)
    {
        KernelThread.AssertCurrent("ke.sim");
        _packet.SetShadow(shadowMap, lightView, lightProjection);
    }

    public void AddShadowDrawCommand(MeshHandle mesh, Matrix4x4 transform)
    {
        KernelThread.AssertCurrent("ke.sim");
        _packet.AddShadowDrawCommand(mesh, transform);
    }

    public void EndShadowPass()
    {
        KernelThread.AssertCurrent("ke.sim");
    }

    public void SetShadowMap(ShadowMapHandle shadowMap)
    {
        KernelThread.AssertCurrent("ke.sim");
        _packet.SetActiveShadowMap(shadowMap);
    }

    public void SetSsao(bool enabled, float radius = 0.5f, float bias = 0.025f, float strength = 1.0f)
    {
        KernelThread.AssertCurrent("ke.sim");
        _packet.SetSsao(enabled, radius, bias, strength);
    }

    public void SetTonemapping(bool enabled, float exposure = 1.0f, float gamma = 2.2f)
    {
        KernelThread.AssertCurrent("ke.sim");
        _packet.SetTonemapping(enabled, exposure, gamma);
    }

    public void SetBloom(bool enabled, float threshold = 1.0f, float intensity = 0.5f)
    {
        KernelThread.AssertCurrent("ke.sim");
        _packet.SetBloom(enabled, threshold, intensity);
    }
}
