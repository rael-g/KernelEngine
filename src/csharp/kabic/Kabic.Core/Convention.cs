namespace Kabic;

/// <summary>
/// The naming and shape conventions of the C ABI being compiled — everything
/// `kabic` "knows" about its consumer that is NOT intrinsic to C itself.
/// </summary>
/// <remarks>
/// <para>
/// A C ABI does not say what a fallible call looks like, how ownership is
/// expressed, or which function is a factory — those are a project's own
/// vocabulary. `Classifier` needs that vocabulary to classify anything, but it
/// should not *contain* it: with the rules inlined, a reader could not tell a
/// structural inference (a vtable is a struct holding function pointers — true
/// of any C ABI) from a project-specific spelling (a trailing `ke_error**`
/// means fallible — true only here), and any consumer renaming its prefix would
/// have to edit the classifier's logic.
/// </para>
/// <para>
/// Deliberately still a hardcoded instance rather than a parameter: a second
/// real consumer would be needed to know which axes genuinely vary, and
/// inventing that shape from one data point risks getting it wrong. The debt is
/// recorded in <c>docs/ScriptingArchitectureV3.md</c> — the eventual split is
/// a `kabic` core that takes a <c>Convention</c> plus a thin per-project
/// definition supplying one.
/// </para>
/// </remarks>
public sealed class Convention
{
    /// <summary>Prefix every public symbol in this ABI carries (<c>ke_input</c>, <c>ke_logger_create</c>).</summary>
    public required string SymbolPrefix { get; init; }

    /// <summary>
    /// Suffix marking an owner-wrapper struct (<c>ke_input_handle{ref, destroy}</c>) — a plain
    /// lifetime holder, not a vtable a caller registers a provider or callback for.
    /// </summary>
    public required string HandleSuffix { get; init; }

    /// <summary>Suffix marking a factory function for the vtable it is named after (<c>ke_input_create</c>).</summary>
    public required string FactorySuffix { get; init; }

    /// <summary>
    /// The out-parameter type spelling that makes a slot fallible. A slot returning boolean-true-on-success
    /// whose last parameter is this type reports failure through it rather than through its return value.
    /// </summary>
    public required string ErrorOutParamType { get; init; }

    /// <summary>Boolean return-type spellings that mean "succeeded", paired with <see cref="ErrorOutParamType"/>.</summary>
    public required IReadOnlyList<string> BooleanReturnTypes { get; init; }

    /// <summary>True if <paramref name="structName"/> names an owner-wrapper rather than a real vtable.</summary>
    public bool IsHandleType(string structName) => structName.EndsWith(HandleSuffix);

    /// <summary>The owner-wrapper struct name paired with a given vtable (<c>ke_window</c> → <c>ke_window_handle</c>).</summary>
    public string HandleTypeFor(string vtableName) => vtableName + HandleSuffix;

    /// <summary>The factory function name paired with a given vtable (<c>ke_input</c> → <c>ke_input_create</c>).</summary>
    public string FactoryNameFor(string vtableName) => vtableName + FactorySuffix;

    /// <summary>True if <paramref name="functionName"/> is spelled as a factory for some vtable.</summary>
    public bool IsFactoryName(string functionName) => functionName.EndsWith(FactorySuffix);

    /// <summary>True if this parameter is the trailing error out-parameter that makes a slot fallible.</summary>
    public bool IsErrorOutParam(ApiParam p) =>
        p.Type.Replace(" ", "").Contains(ErrorOutParamType.Replace(" ", ""));

    /// <summary>True if a slot with this return type and parameter list reports failure via an error out-param.</summary>
    public bool IsFallible(string returns, IReadOnlyList<ApiParam> parameters) =>
        BooleanReturnTypes.Contains(returns) && parameters.Count > 0 && IsErrorOutParam(parameters[^1]);

    /// <summary>
    /// Explicit target-language type names for ABI symbols whose derived name is
    /// unusable — chiefly a vtable whose name matches its own namespace's last
    /// segment (<c>ke_ecs</c> in <c>KernelEngine.Ecs</c> would derive to
    /// <c>Ecs</c>, forcing every reference to be fully qualified).
    /// </summary>
    public IReadOnlyDictionary<string, string> TypeNameOverrides { get; init; } =
        new Dictionary<string, string>();

    /// <summary>Strips <see cref="SymbolPrefix"/> from a symbol, leaving the rest untouched.</summary>
    public string StripPrefix(string name) =>
        name.StartsWith(SymbolPrefix) ? name[SymbolPrefix.Length..] : name;

    /// <summary>
    /// KernelEngine's ABI vocabulary. The one hardcoded instance today; see the
    /// class remarks for why it is not yet a parameter.
    /// </summary>
    public static readonly Convention KernelEngine = new()
    {
        SymbolPrefix = "ke_",
        HandleSuffix = "_handle",
        FactorySuffix = "_create",
        ErrorOutParamType = "ke_error**",
        // C spells `bool` as `_Bool` after preprocessing; both reach the description.
        BooleanReturnTypes = ["_Bool", "bool"],
        TypeNameOverrides = new Dictionary<string, string>
        {
            // Would derive to `Ecs` inside namespace KernelEngine.Ecs, making the
            // type unreferenceable without full qualification everywhere.
            ["ke_ecs"] = "EcsRegistry",
        },
    };
}
