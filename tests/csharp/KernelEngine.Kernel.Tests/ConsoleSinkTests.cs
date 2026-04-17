using KernelEngine.Kernel.Native;
using Xunit;

namespace KernelEngine.Kernel.Tests;

public class ConsoleSinkTests
{
    [Fact]
    public void Log_WritesToConsoleError()
    {
        var sink = new ConsoleSink();
        var sw = new StringWriter();
        var old = Console.Error;
        Console.SetError(sw);
        
        try
        {
            sink.Log(ke_log_level.KE_LOG_LEVEL_INFO, "TestTag", "TestMessage");
            var output = sw.ToString();
            Assert.Contains("[INFO] TestTag: TestMessage", output);
        }
        finally
        {
            Console.SetError(old);
        }
    }

    [Fact]
    public void Log_HandlesUnknownLevel()
    {
        var sink = new ConsoleSink();
        var sw = new StringWriter();
        var old = Console.Error;
        Console.SetError(sw);
        
        try
        {
            sink.Log((ke_log_level)99, "Tag", "Msg");
            var output = sw.ToString();
            Assert.Contains("[?] Tag: Msg", output);
        }
        finally
        {
            Console.SetError(old);
        }
    }
}
