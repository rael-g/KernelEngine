using KernelEngine.Kernel;
using Xunit;

namespace KernelEngine.Kernel.Tests;

public class LoggerTests
{
    [Fact]
    public void Logger_CanBeCreatedAndDestroyed()
    {
        using var allocator = new MallocAllocator();
        var logger = new Logger(allocator);
        // implicit destroy via finalizer or we could make it IDisposable
        // Logger in its current impl doesn't seem to be IDisposable but maybe it should be.
    }

    [Fact]
    public void Logger_CanLogWithSink()
    {
        using var allocator = new MallocAllocator();
        var logger = new Logger(allocator);
        var sink = new ConsoleSink { MinLevel = Kernel.Native.ke_log_level.KE_LOG_LEVEL_TRACE };
        logger.AddSink(sink);
        
        logger.Info("Testing C# logger interop", "TEST");
    }
}
