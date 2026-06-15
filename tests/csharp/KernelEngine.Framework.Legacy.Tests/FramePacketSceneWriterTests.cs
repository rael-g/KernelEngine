using System.Numerics;
using KernelEngine.Framework.Legacy;
using KernelEngine.Kernel;
using NSubstitute;
using Xunit;

namespace KernelEngine.Framework.Legacy.Tests;

public class FramePacketSceneWriterTests
{
    [Fact]
    public void AllMethods_AssertThreadAndDelegateToPacket()
    {
        var mockPacket = Substitute.For<IFramePacket>();
        var mockFactory = Substitute.For<IKernelFactory>();
        var writer = new FramePacketSceneWriter(mockPacket, mockFactory);

        writer.ClearColor(1, 0, 0, 1);
        mockFactory.Received().AssertCurrentThread("ke.sim");
        mockPacket.Received().SetClearColor(1, 0, 0, 1);

        writer.SetAmbientLight(0.1f, 0.1f, 0.1f);
        mockPacket.Received().SetAmbientLight(0.1f, 0.1f, 0.1f);

        var view = Matrix4x4.Identity;
        var proj = Matrix4x4.Identity;
        var pos = Vector3.Zero;
        writer.SetCamera(view, proj, pos);
        mockPacket.Received().SetCamera(view, proj, pos);

        writer.SetDirectionalLight(Vector3.UnitY, Vector3.One, 1.0f);
        mockPacket.Received().SetDirectionalLight(Arg.Is<DirectionalLightData>(d => 
            d.Direction == Vector3.UnitY && d.Color == Vector3.One && d.Intensity == 1.0f));

        writer.AddDrawCommand(new MeshHandle(1), new MaterialHandle(2), Matrix4x4.Identity);
        mockPacket.Received().AddDrawCommand(new MeshHandle(1), new MaterialHandle(2), Matrix4x4.Identity);

        writer.SetSkybox(new TextureHandle(3));
        mockPacket.Received().SetSkybox(new TextureHandle(3));

        writer.BeginShadowPass(new ShadowMapHandle(4), view, proj);
        mockPacket.Received().SetShadow(new ShadowMapHandle(4), view, proj);

        writer.AddShadowDrawCommand(new MeshHandle(1), Matrix4x4.Identity);
        mockPacket.Received().AddShadowDrawCommand(new MeshHandle(1), Matrix4x4.Identity);

        writer.EndShadowPass();
        
        writer.SetShadowMap(new ShadowMapHandle(4));
        mockPacket.Received().SetActiveShadowMap(new ShadowMapHandle(4));

        writer.SetSsao(true);
        mockPacket.Received().SetSsao(true, 0.5f, 0.025f, 1.0f);

        writer.SetTonemapping(true);
        mockPacket.Received().SetTonemapping(true, 1.0f, 2.2f);

        writer.SetBloom(true);
        mockPacket.Received().SetBloom(true, 1.0f, 0.5f);
    }
}
