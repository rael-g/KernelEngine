using System.Collections.Concurrent;
using System.Runtime.CompilerServices;

using Microsoft.Extensions.Logging;

namespace KernelEngine.Logger;

/// <summary>
/// Routes the lines native libraries log into a <see cref="ILoggerFactory"/>, so native and managed
/// code write to the same providers at the same levels.
/// </summary>
public static unsafe class NativeLogging
{
    private static readonly ConditionalWeakTable<ILoggerFactory, Context> s_contexts = new();

    /// <summary>The callback a native <c>&lt;library&gt;_set_log_callback</c> takes.</summary>
    public static delegate* unmanaged[Cdecl]<void*, LogLevel, sbyte*, sbyte*, void> Callback => LogCallbackNative.Pointer;

    /// <summary>
    /// The context a native <c>&lt;library&gt;_set_log_callback</c> takes with <see cref="Callback"/>:
    /// each line is logged to the logger <paramref name="factory"/> creates for the line's scope, at
    /// the level of the same name. The same factory always yields the same context, kept alive for as
    /// long as the process runs.
    /// </summary>
    public static void* ContextOf(ILoggerFactory factory)
    {
        ArgumentNullException.ThrowIfNull(factory);
        return s_contexts.GetValue(factory, f => new Context(f)).Pinned;
    }

    private sealed class Context
    {
        private readonly ILoggerFactory _factory;
        private readonly ConcurrentDictionary<string, ILogger> _loggers = new();

        public Context(ILoggerFactory factory)
        {
            _factory = factory;
            Pinned = LogCallbackNative.Pin(Log);
        }

        public void* Pinned { get; }

        private void Log(LogLevel level, string scope, string message) =>
            _loggers.GetOrAdd(scope, _factory.CreateLogger).Log((Microsoft.Extensions.Logging.LogLevel)level, "{Message}", message);
    }
}
