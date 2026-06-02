using System.Numerics;
using Xunit;
using NSubstitute;
using KernelEngine.Kernel;
using System.Reflection;

namespace KernelEngine.Framework.Tests;

public class LabelRenderSystemTests
{
    private Font CreateMockFont(GlyphMetrics[] glyphs)
    {
        var factory = Substitute.For<IResourceFactory>();
        var texture = (Texture)Activator.CreateInstance(
            typeof(Texture), 
            BindingFlags.NonPublic | BindingFlags.Instance, 
            null, 
            new object[] { factory, new TextureHandle(1) }, 
            null)!;

        return (Font)Activator.CreateInstance(
            typeof(Font), 
            BindingFlags.NonPublic | BindingFlags.Instance, 
            null, 
            new object[] { texture, glyphs, 16f, 10f }, 
            null)!;
    }

    [Fact]
    public void Update_EmitsQuads_ForLabels()
    {
        var font = CreateMockFont(new[] { 
            new GlyphMetrics { Codepoint = 'A', AdvanceX = 10f, Width = 8f, Height = 12f } 
        });

        var label = new Label { Text = "A", Font = font };
        var startMethod = typeof(Node).GetMethod("Start", BindingFlags.NonPublic | BindingFlags.Instance);
        startMethod!.Invoke(label, null);

        var packet = Substitute.For<IFramePacket>();
        var system = new LabelRenderSystem(() => (800, 600));

        system.Update(null!, 0.016f, packet);

        packet.Received(1).AddUiQuadCommand(
            Arg.Any<TextureHandle>(),
            Arg.Any<float>(), Arg.Any<float>(), Arg.Any<float>(), Arg.Any<float>(),
            Arg.Any<float>(), Arg.Any<float>(), Arg.Any<float>(), Arg.Any<float>(),
            Arg.Any<float>(), Arg.Any<float>(), Arg.Any<float>(), Arg.Any<float>());

        // Cleanup
        var onDestroyMethod = typeof(Node).GetMethod("OnDestroy", BindingFlags.NonPublic | BindingFlags.Instance);
        onDestroyMethod!.Invoke(label, null);
    }

    [Fact]
    public void Update_DoesNothing_WhenNoPacket()
    {
        var system = new LabelRenderSystem(() => (800, 600));
        system.Update(null!, 0.016f, null);
        // Should not throw
    }

    [Fact]
    public void Update_DoesNothing_WhenNoLabels()
    {
        var packet = Substitute.For<IFramePacket>();
        var system = new LabelRenderSystem(() => (800, 600));
        system.Update(null!, 0.016f, packet);
        packet.DidNotReceiveWithAnyArgs().AddUiQuadCommand(
            default, default, default, default, default, 
            default, default, default, default, 
            default, default, default, default);
    }
}
