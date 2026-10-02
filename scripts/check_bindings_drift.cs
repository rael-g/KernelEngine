#!/usr/bin/env dotnet run

using System.Diagnostics;
using System.Runtime.CompilerServices;

static string ScriptDir([CallerFilePath] string path = "") => Path.GetDirectoryName(path)!;

Console.WriteLine("Checking for bindings drift (headers vs. generated C#)...");

using var process = new Process
{
    StartInfo = new ProcessStartInfo("dotnet"),
};
foreach (var a in new[] { "run", Path.Combine(ScriptDir(), "generate_bindings.cs"), "--", "--check" })
    process.StartInfo.ArgumentList.Add(a);
process.Start();
process.WaitForExit();
return process.ExitCode;
