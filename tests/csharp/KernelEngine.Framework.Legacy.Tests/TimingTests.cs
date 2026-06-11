using Xunit;
using KernelEngine.Framework.Legacy;
using System.Threading;

namespace KernelEngine.Framework.Legacy.Tests;

public class TimeTests
{
    [Fact]
    public void ElapsedTime_Increases()
    {
        float t1 = Time.ElapsedTime;
        Thread.Sleep(10);
        float t2 = Time.ElapsedTime;
        Assert.True(t2 >= t1);
    }

    [Fact]
    public void NewFrame_CalculatesDeltaTime()
    {
        Time.NewFrame();
        Thread.Sleep(50);
        Time.NewFrame();
        
        Assert.True(Time.DeltaTime > 0.04f);
    }
}
