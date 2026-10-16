using ClangSharp;
using ClangSharp.Interop;

using static ClangSharp.Interop.CXDiagnosticSeverity;
using static ClangSharp.Interop.CXErrorCode;
using static ClangSharp.Interop.CXTranslationUnit_Flags;

namespace Kabic.Bindings;

/// <summary>
/// Runs the ClangSharp generator for one <c>BindingJob</c> and reports what it logged.
/// </summary>
public static class ClangSharpRunner
{
    static readonly string[] FixedRemaps = ["uint64_t=ulong", "int64_t=long"];

    /// <summary>
    /// Generates the bindings of <paramref name="job"/> into <paramref name="outputDirectory"/>, with
    /// the <c>using</c> directives of each file ordered by <see cref="UsingBlock"/>.
    /// Returns whether no error was counted, with the log of what the parse and the generator
    /// reported. The current directory is the job's native directory while the generator runs and
    /// is restored afterwards, also when it throws.
    /// </summary>
    public static BindingRun Run(BindingJob job, string rootDir, string resourceDir, string outputDirectory)
    {
        var umbrellaDir = Path.Combine(rootDir, "build", "kabic", "umbrellas");
        string file;
        if (job.UmbrellaBody is not null)
        {
            Directory.CreateDirectory(umbrellaDir);
            file = Path.Combine(umbrellaDir, job.File);
            File.WriteAllText(file, job.UmbrellaBody);
        }
        else
        {
            file = Path.GetFullPath(Path.Combine(job.NativeDir, job.File));
        }
        file = Path.GetRelativePath(job.NativeDir, file);

        var remaps = new Dictionary<string, string>();
        foreach (var pair in job.Remaps.Concat(FixedRemaps))
        {
            var parts = pair.Split('=', 2);
            remaps[parts[0].TrimEnd()] = parts[1].TrimStart();
        }

        var options = OperatingSystem.IsWindows() ? PInvokeGeneratorConfigurationOptions.None : PInvokeGeneratorConfigurationOptions.GenerateUnixTypes;
        foreach (var flag in job.Config) options = Apply(options, flag);

        var config = new PInvokeGeneratorConfiguration("c++", "", job.Namespace, outputDirectory, "", PInvokeGeneratorOutputMode.CSharp, options)
        {
            DefaultClass = job.MethodsClass,
            ExcludedNames = job.Excludes.ToArray(),
            LibraryPath = job.Library ?? "",
            MethodPrefixToStrip = job.MethodPrefix,
            RemappedNames = remaps,
            TraversalNames = job.Traverse.ToArray(),
            WithUsings = job.CommonNamespace.Length == 0 || job.Namespace == job.CommonNamespace
                ? new Dictionary<string, IReadOnlyList<string>>()
                : new Dictionary<string, IReadOnlyList<string>> { ["*"] = new List<string> { job.CommonNamespace } },
        };

        var clangArgs = new List<string> { "--language=c++", "-Wno-pragma-once-outside-header" };
        clangArgs.AddRange(job.IncludeDirectories.Select(d => $"--include-directory={d}"));
        clangArgs.Add($"-resource-dir={resourceDir}");
        clangArgs.AddRange(job.Additional);

        var flags = CXTranslationUnit_IncludeAttributedTypes | CXTranslationUnit_VisitImplicitAttributes;
        if (config.GenerateMacroBindings) flags |= CXTranslationUnit_DetailedPreprocessingRecord;

        var log = new List<string>();
        var errors = 0;
        var previous = Directory.GetCurrentDirectory();
        Directory.SetCurrentDirectory(job.NativeDir);
        try
        {
            using var generator = new PInvokeGenerator(config);
            var error = CXTranslationUnit.TryParse(generator.IndexHandle, file, clangArgs.ToArray(), [], flags, out var handle);
            var skip = false;
            if (error != CXError_Success)
            {
                log.Add($"parsing failed for '{file}': {error}");
                skip = true;
            }
            else
            {
                for (uint i = 0; i < handle.NumDiagnostics; ++i)
                {
                    using var diagnostic = handle.GetDiagnostic(i);
                    log.Add(diagnostic.Format(CXDiagnostic.DefaultDisplayOptions).ToString());
                    skip |= diagnostic.Severity is CXDiagnostic_Error or CXDiagnostic_Fatal;
                }
            }

            if (skip)
            {
                errors++;
            }
            else
            {
                using var translationUnit = TranslationUnit.GetOrCreate(handle);
                generator.GenerateBindings(translationUnit, file, clangArgs.ToArray(), flags);
            }

            foreach (var diagnostic in generator.Diagnostics)
            {
                log.Add(diagnostic.ToString());
                if (diagnostic.Level == DiagnosticLevel.Error) errors++;
            }
        }
        finally
        {
            Directory.SetCurrentDirectory(previous);
        }

        UsingBlock.NormalizeDirectory(outputDirectory);
        return new BindingRun(errors == 0, log);
    }

    static PInvokeGeneratorConfigurationOptions Apply(PInvokeGeneratorConfigurationOptions options, string flag) => flag switch
    {
        "multi-file" => options | PInvokeGeneratorConfigurationOptions.GenerateMultipleFiles,
        "latest-codegen" => (options & ~PInvokeGeneratorConfigurationOptions.GenerateCompatibleCode & ~PInvokeGeneratorConfigurationOptions.GeneratePreviewCode) | PInvokeGeneratorConfigurationOptions.GenerateLatestCode,
        "generate-helper-types" => options | PInvokeGeneratorConfigurationOptions.GenerateHelperTypes,
        "generate-file-scoped-namespaces" => options | PInvokeGeneratorConfigurationOptions.GenerateFileScopedNamespaces,
        "exclude-funcs-with-body" => options | PInvokeGeneratorConfigurationOptions.ExcludeFunctionsWithBody,
        "generate-disable-runtime-marshalling" => options | PInvokeGeneratorConfigurationOptions.GenerateDisableRuntimeMarshalling,
        "generate-macro-bindings" => options | PInvokeGeneratorConfigurationOptions.GenerateMacroBindings,
        _ => throw new InvalidOperationException($"unknown ClangSharp config switch '{flag}'"),
    };
}

/// <summary>
/// The outcome of one <see cref="ClangSharpRunner.Run"/>: whether it counted no error, and the log
/// of what was reported.
/// </summary>
public sealed record BindingRun(bool Succeeded, IReadOnlyList<string> Log);
