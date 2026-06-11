using System.Numerics;
using Xunit;
using NSubstitute;
using KernelEngine.Kernel;
using System.Reflection;

namespace KernelEngine.Framework.Legacy.Tests;

public class LabelRenderSystemTests
{
    private IResourceCacheBackend? _cache;

    private Font CreateMockFont(GlyphMetrics[] glyphs)
    {
        FrameworkBackends.Default ??= new NativeFrameworkBackendFactory();
        _cache ??= FrameworkBackends.Required.CreateResourceCache();
        // Register the synthetic handle so subsequent Retain/Release in the Label lifecycle
        // resolve cleanly in the native cache.
        _cache.RegisterResource(1u, () => { });
        var texture = (Texture)Activator.CreateInstance(
            typeof(Texture),
            BindingFlags.NonPublic | BindingFlags.Instance,
            null,
            new object[] { _cache, new TextureHandle(1) },
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
    public void Update_CalculatesAlignmentOffsets()
    {
        var font = CreateMockFont(new[] { 
            new GlyphMetrics { Codepoint = 'A', AdvanceX = 10f, Width = 8f, Height = 12f } 
        });

        // Center aligned via anchor
        var label = new Label { Text = "A", Font = font, Anchor = new Vector2(0.5f, 0f) };
        var startMethod = typeof(Node).GetMethod("Start", BindingFlags.NonPublic | BindingFlags.Instance);
        startMethod!.Invoke(label, null);

        var packet = Substitute.For<IFramePacket>();
        var system = new LabelRenderSystem(() => (800, 600));

        system.Update(null!, 0.016f, packet);

        // Advance is 10, so offset should be around 395 (400 - 0.5*10)
        packet.Received(1).AddUiQuadCommand(
            Arg.Any<TextureHandle>(),
            Arg.Is<float>(x => x == 395f), // Correct absolute coordinate
            Arg.Any<float>(), Arg.Any<float>(), Arg.Any<float>(),
            Arg.Any<float>(), Arg.Any<float>(), Arg.Any<float>(), Arg.Any<float>(),
            Arg.Any<float>(), Arg.Any<float>(), Arg.Any<float>(), Arg.Any<float>());
            
        // Cleanup
        var onDestroyMethod = typeof(Node).GetMethod("OnDestroy", BindingFlags.NonPublic | BindingFlags.Instance);
        onDestroyMethod!.Invoke(label, null);
    }

    [Fact]
    public void Update_HandlesMultipleCharacters()
    {
        var font = CreateMockFont(new[] { 
            new GlyphMetrics { Codepoint = 'A', AdvanceX = 10f, Width = 8f, Height = 12f },
            new GlyphMetrics { Codepoint = 'B', AdvanceX = 12f, Width = 9f, Height = 12f }
        });

        var label = new Label { Text = "AB", Font = font };
        var startMethod = typeof(Node).GetMethod("Start", BindingFlags.NonPublic | BindingFlags.Instance);
        startMethod!.Invoke(label, null);

        var packet = Substitute.For<IFramePacket>();
        var system = new LabelRenderSystem(() => (800, 600));

        system.Update(null!, 0.016f, packet);

        packet.Received(2).AddUiQuadCommand(
            Arg.Any<TextureHandle>(),
            Arg.Any<float>(), Arg.Any<float>(), Arg.Any<float>(), Arg.Any<float>(),
            Arg.Any<float>(), Arg.Any<float>(), Arg.Any<float>(), Arg.Any<float>(),
            Arg.Any<float>(), Arg.Any<float>(), Arg.Any<float>(), Arg.Any<float>());
            
        // Cleanup
        var onDestroyMethod = typeof(Node).GetMethod("OnDestroy", BindingFlags.NonPublic | BindingFlags.Instance);
        onDestroyMethod!.Invoke(label, null);
    }
}
