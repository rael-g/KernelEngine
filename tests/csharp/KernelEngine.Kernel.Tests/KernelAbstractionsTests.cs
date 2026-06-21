
using NSubstitute;
using Xunit;

namespace EngineTests;

public class KernelAbstractionsTests
{
    [Fact]
    public void InputContext_Current_ThrowsWhenNotSet()
    {
        InputContext.Set(null);
        Assert.Throws<InvalidOperationException>(() => InputContext.Current);
    }

    [Fact]
    public void InputContext_Set_Works()
    {
        var mock = Substitute.For<IInputReader>();
        InputContext.Set(mock);
        Assert.Same(mock, InputContext.Current);
        InputContext.Set(null);
    }
}
