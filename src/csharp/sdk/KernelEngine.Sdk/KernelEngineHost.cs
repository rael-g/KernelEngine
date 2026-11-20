using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;

using KernelEngine.Assembly;
using KernelEngine.Runner.Native;

using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

using NativeResult = KernelEngine.Result.Native.Result;

namespace KernelEngine;

/// <summary>
/// The host of an engine assembled from parts, owner of the thread that starts it. Starting it opens the assembly,
/// writes the composition into it, resolves it and creates every instance; running it runs the instance
/// <c>runner</c> on the calling thread until it ends; stopping it destroys every instance, the last made first.
/// </summary>
public sealed unsafe class KernelEngineHost : IHost
{
    readonly Func<IServiceProvider, KernelEngine.Assembly.Assembly> _open;
    readonly Action<KernelEngine.Assembly.Assembly>[] _compose;
    KernelEngine.Assembly.Assembly? _assembly;
    GCHandle _logging;

    internal KernelEngineHost(IServiceProvider services, Func<IServiceProvider, KernelEngine.Assembly.Assembly> open, Action<KernelEngine.Assembly.Assembly>[] compose)
    {
        Services = services;
        _open = open;
        _compose = compose;
    }

    /// <summary>The container the host was registered in.</summary>
    public IServiceProvider Services { get; }

    /// <summary>Whether the host started and has not stopped since.</summary>
    public bool Started => _assembly is not null;

    /// <summary>Gives the instance <paramref name="name"/> as the vtable of <paramref name="contract"/>.</summary>
    /// <exception cref="InvalidOperationException">The host has not started.</exception>
    /// <exception cref="KeyNotFoundException">No instance has that name or it does not provide the contract.</exception>
    public nint Instance(string name, string contract) =>
        (_assembly ?? throw new InvalidOperationException($"the instance {name} is asked for before the engine host started")).Get(name, contract);

    /// <summary>
    /// Opens the assembly, sends the parts' log lines to the container's <see cref="ILoggerFactory"/> when it has
    /// one, writes the composition, resolves it and creates every instance. Does nothing when started.
    /// </summary>
    /// <exception cref="InvalidOperationException">The composition cannot be assembled; the message lists every reason.</exception>
    public void Start()
    {
        if (_assembly is not null) return;
        var assembly = _open(Services);
        try
        {
            if (Services.GetService<ILoggerFactory>() is { } logging)
            {
                _logging = GCHandle.Alloc(logging);
                assembly.RouteLog((nint)(delegate* unmanaged[Cdecl]<void*, KernelEngine.Logger.LogLevel, sbyte*, sbyte*, void>)&Log, GCHandle.ToIntPtr(_logging));
            }
            foreach (var compose in _compose) compose(assembly);
            var reasons = new List<string>();
            try
            {
                assembly.Resolve((failure, instance, name, detail) => reasons.Add($"{failure} {instance} {name}: {detail}"));
            }
            catch (Exception failed)
            {
                throw new InvalidOperationException($"the composition cannot be assembled:{Environment.NewLine}{string.Join(Environment.NewLine, reasons)}", failed);
            }
            var native = ((INativeAssembly)assembly).Native;
            var made = NativeResult.Pending;
            while (made == NativeResult.Pending) made = native->advance(native);
            if (made != NativeResult.Ok) throw new InvalidOperationException($"creating the instances failed with {made}");
        }
        catch
        {
            assembly.Dispose();
            ReleaseLogging();
            throw;
        }
        _assembly = assembly;
    }

    /// <summary>Runs the instance <c>runner</c> on the calling thread until it ends, starting the host first when it has not.</summary>
    /// <exception cref="Exception">Starting failed, or the runner ended with a failure.</exception>
    public void Run()
    {
        Start();
        Runner.Runner.Borrow((ke_runner*)Instance("runner", "ke_runner")).Run();
    }

    /// <summary>Destroys every instance, the last made first. Does nothing when not started.</summary>
    public void Stop()
    {
        _assembly?.Dispose();
        _assembly = null;
        ReleaseLogging();
    }

    /// <inheritdoc/>
    public Task StartAsync(CancellationToken cancellationToken = default)
    {
        Start();
        return Task.CompletedTask;
    }

    /// <inheritdoc/>
    public Task StopAsync(CancellationToken cancellationToken = default)
    {
        Stop();
        return Task.CompletedTask;
    }

    /// <summary>Stops the host.</summary>
    public void Dispose() => Stop();

    void ReleaseLogging()
    {
        if (_logging.IsAllocated) _logging.Free();
    }

    [UnmanagedCallersOnly(CallConvs = [typeof(CallConvCdecl)])]
    static void Log(void* ctx, KernelEngine.Logger.LogLevel level, sbyte* scope, sbyte* message)
    {
        if (GCHandle.FromIntPtr((nint)ctx).Target is not ILoggerFactory logging) return;
        var logger = logging.CreateLogger(Marshal.PtrToStringUTF8((nint)scope) ?? "");
        logger.Log(level switch
        {
            KernelEngine.Logger.LogLevel.Trace => LogLevel.Trace,
            KernelEngine.Logger.LogLevel.Debug => LogLevel.Debug,
            KernelEngine.Logger.LogLevel.Info => LogLevel.Information,
            KernelEngine.Logger.LogLevel.Warning => LogLevel.Warning,
            KernelEngine.Logger.LogLevel.Error => LogLevel.Error,
            _ => LogLevel.Critical,
        }, "{Message}", Marshal.PtrToStringUTF8((nint)message));
    }
}
