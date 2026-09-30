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
    /// Suffix marking a parameter bag (<c>ke_runtime_system_params</c>) — a value the caller
    /// fills in and passes by pointer to one call, never an interface. Holding a function
    /// pointer does not make it one: a registration bag carries the callback being registered
    /// (<c>execute</c>, <c>on_load</c>) right next to its plain data fields, so slot count
    /// alone cannot tell the two apart, and mistaking a bag for a vtable emits a wrapper class
    /// with <c>Borrow</c>/<c>Dispose</c> around what is not an object. The ABI guarantees this
    /// suffix for every parameter bag, which is what makes it a sound discriminator.
    /// </summary>
    public required string ParamsSuffix { get; init; }

    /// <summary>Whether a struct name marks a parameter bag rather than an interface.</summary>
    public bool IsParamsType(string structName) => structName.EndsWith(ParamsSuffix);

    /// <summary>
    /// Suffix marking an ECS component struct (<c>ke_point_light_component</c>). Stripped
    /// along with <see cref="SymbolPrefix"/> to recover the name the component is registered
    /// under at runtime (<c>point_light</c>), which is its only cross-language identity.
    /// </summary>
    public required string ComponentSuffix { get; init; }

    /// <summary>Whether a struct name marks an ECS component rather than plain value data.</summary>
    public bool IsComponentType(string structName) => structName.EndsWith(ComponentSuffix);

    /// <summary>The registered component name for a component struct (<c>ke_point_light_component</c> → <c>point_light</c>).</summary>
    public string ComponentNameFor(string structName)
    {
        var n = StripPrefix(structName);
        return n.EndsWith(ComponentSuffix) ? n[..^ComponentSuffix.Length] : n;
    }

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

    /// <summary>
    /// True if a slot reports failure through a trailing error out-parameter — whatever
    /// it returns. A boolean-returning slot signals failure with the return value; one
    /// returning a value signals it by writing the out-param (which stays NULL on
    /// success), so both are fallible and neither should expose the parameter.
    /// </summary>
    public bool IsFallible(string returns, IReadOnlyList<ApiParam> parameters) =>
        parameters.Count > 0 && IsErrorOutParam(parameters[^1]);

    /// <summary>True if this slot signals failure through its boolean return rather than by writing the error out-param.</summary>
    public bool SignalsFailureByReturn(string returns) => BooleanReturnTypes.Contains(returns);

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
        ComponentSuffix = "_component",
        ParamsSuffix = "_params",
        ErrorOutParamType = "ke_error**",
        BooleanReturnTypes = ["_Bool", "bool", "ke_bool"],
        TypeNameOverrides = new Dictionary<string, string>
        {
            ["ke_ecs"] = "EcsRegistry",
            ["ke_asset_resolver"] = "NativeAssetResolver",
            ["ke_input_actions"] = "NativeInputActions",
            ["ke_physics_2d"] = "Physics2D",
            ["ke_body_type_2d"] = "BodyType2D",
            ["ke_phase"] = "RuntimePhase",
            ["ke_access"] = "RuntimeAccess",
        },
    };
}
