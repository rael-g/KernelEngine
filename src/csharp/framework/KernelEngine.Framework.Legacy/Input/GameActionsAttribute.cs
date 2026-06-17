namespace KernelEngine.Framework.Legacy;

/// <summary>
/// Marks an int-backed enum as the game's input-action verbs. The parameterless
/// <c>services.AddInputActions()</c> scans loaded assemblies for enums carrying this attribute
/// and auto-registers each via <see cref="InputActionsServiceExtensions.AddInputActions{TEnum}"/>.
/// </summary>
/// <remarks>
/// <para>
/// Goal: game code never edits <c>Program.cs</c> to wire a new action set. Declaring the enum
/// (with this attribute) is the only touch point. The bindings file (<c>actions.input</c>) declared
/// in <c>Project</c> still drives runtime — this attribute only tells the framework <i>which</i>
/// enum type to bind it against.
/// </para>
/// <para>
/// Multiple <c>[GameActions]</c> enums are allowed (e.g. one for gameplay, one for menus) — each
/// gets registered as its own <see cref="IInputActionReader{TEnum}"/> service.
/// </para>
/// </remarks>
[AttributeUsage(AttributeTargets.Enum, AllowMultiple = false, Inherited = false)]
public sealed class GameActionsAttribute : Attribute;
