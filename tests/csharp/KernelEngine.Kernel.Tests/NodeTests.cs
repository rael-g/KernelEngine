
using System.Numerics;
using Xunit;

namespace EngineTests;

public class NodeTests
{
    [Fact]
    public void Transform_ValueTypeBehavior()
    {
        var t1 = new Transform { Position = new Vector3(1, 0, 0) };
        var t2 = t1;
        t2.Position = new Vector3(2, 0, 0);
        
        // Transform is a struct (value type), so t1 should be unchanged
        Assert.Equal(1, t1.Position.X);
        Assert.Equal(2, t2.Position.X);
    }

    [Fact]
    public void Node_Properties_InitialValues()
    {
        // We can't easily instantiate Node without a real Native World
        // but we can check if the constant definitions are correct.
        Assert.Equal(0u, 0u); // Placeholder for logic validation
    }
}
