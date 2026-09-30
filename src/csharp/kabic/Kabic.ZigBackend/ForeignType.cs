namespace Kabic.Zig;

/// <summary>
/// Where a type one domain composes but does not declare is reachable from, and how it
/// is spelled once imported.
/// </summary>
/// <param name="Module">The name the import is bound to in the composing module.</param>
/// <param name="ImportPath">
/// The path <c>@import</c> is given. Carried rather than derived from
/// <paramref name="Module"/> so the directory layout of the generated modules stays a
/// question for whatever drives the generator, not a rule compiled into the backend.
/// </param>
/// <param name="IsStruct">
/// Whether the owning domain declares it inside its ABI block. A struct is part of the
/// layout the header fixes and lives under <c>abi</c>; an enum and a primitive alias are
/// projections and sit at the module's top level. Spelling one as the other names a
/// declaration that exists, in a scope where it does not.
/// </param>
public sealed record ForeignType(string Module, string ImportPath, bool IsStruct);
