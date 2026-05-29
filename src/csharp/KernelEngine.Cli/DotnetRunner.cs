using System.Diagnostics;
using System.Text;

namespace KernelEngine.Cli;

/// <summary>
/// Thin wrapper around <c>dotnet</c> CLI invocations. We never want to swallow output silently —
/// when a scaffolding step fails the user needs to see the SDK's own diagnostics, not a generic
/// "command failed" wrapper. Output is captured and surfaced on non-zero exit.
/// </summary>
public static class DotnetRunner
{
    public static void Run(params string[] args)
    {
        var psi = new ProcessStartInfo
        {
            FileName               = "dotnet",
            RedirectStandardOutput = true,
            RedirectStandardError  = true,
            UseShellExecute        = false,
        };
        foreach (var a in args) psi.ArgumentList.Add(a);

        using var p = Process.Start(psi) ?? throw new InvalidOperationException("Failed to start `dotnet`.");
        var stdout = new StringBuilder();
        var stderr = new StringBuilder();
        p.OutputDataReceived += (_, e) => { if (e.Data != null) stdout.AppendLine(e.Data); };
        p.ErrorDataReceived  += (_, e) => { if (e.Data != null) stderr.AppendLine(e.Data); };
        p.BeginOutputReadLine();
        p.BeginErrorReadLine();
        p.WaitForExit();

        if (p.ExitCode != 0)
        {
            throw new InvalidOperationException(
                $"`dotnet {string.Join(' ', args)}` exited with code {p.ExitCode}.{Environment.NewLine}" +
                $"stdout: {stdout}{Environment.NewLine}stderr: {stderr}");
        }
    }
}
