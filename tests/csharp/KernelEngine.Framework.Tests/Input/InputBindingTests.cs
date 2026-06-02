using Xunit;
using NSubstitute;
using KernelEngine.Kernel;

namespace KernelEngine.Framework.Tests;

public class InputBindingTests
{
    [Fact]
    public void KeyBinding_SamplesCorrectValue()
    {
        var reader = Substitute.For<IInputReader>();
        reader.IsKeyDown((int)Key.Space).Returns(true);
        var binding = new KeyBinding(Key.Space);

        binding.Sample(reader, out float x, out _, out _);
        Assert.Equal(1f, x);
    }

    [Fact]
    public void MouseButtonBinding_SamplesCorrectValue()
    {
        var reader = Substitute.For<IInputReader>();
        reader.IsMouseButtonDown((int)MouseButton.Left).Returns(true);
        var binding = new MouseButtonBinding(MouseButton.Left);

        binding.Sample(reader, out float x, out _, out _);
        Assert.Equal(1f, x);
    }

    [Fact]
    public void KeyPairAxis1DBinding_SamplesCorrectValue()
    {
        var reader = Substitute.For<IInputReader>();
        reader.IsKeyDown((int)Key.A).Returns(true);
        reader.IsKeyDown((int)Key.D).Returns(false);
        var binding = new KeyPairAxis1DBinding(Key.A, Key.D);

        binding.Sample(reader, out float x, out _, out _);
        Assert.Equal(-1f, x);
    }

    [Fact]
    public void KeyPairAxis1DBinding_CancelsToZero()
    {
        var reader = Substitute.For<IInputReader>();
        reader.IsKeyDown((int)Key.A).Returns(true);
        reader.IsKeyDown((int)Key.D).Returns(true);
        var binding = new KeyPairAxis1DBinding(Key.A, Key.D);

        binding.Sample(reader, out float x, out _, out _);
        Assert.Equal(0f, x);
    }

    [Fact]
    public void KeyQuadAxis2DBinding_SamplesCorrectValue()
    {
        var reader = Substitute.For<IInputReader>();
        reader.IsKeyDown((int)Key.W).Returns(true);
        reader.IsKeyDown((int)Key.D).Returns(true);
        var binding = new KeyQuadAxis2DBinding(Key.W, Key.S, Key.A, Key.D);

        binding.Sample(reader, out float x, out float y, out _);
        Assert.Equal(1f, x); // D = Right = +X
        Assert.Equal(1f, y); // W = Up = +Y
    }
}
