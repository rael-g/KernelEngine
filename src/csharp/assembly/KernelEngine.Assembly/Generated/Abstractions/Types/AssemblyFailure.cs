using System.Numerics;

using global::KernelEngine.Ecs;

namespace KernelEngine.Assembly;

public enum AssemblyFailure : uint
{
    UnknownPart = 1,
    UnknownName = 2,
    Unsatisfied = 3,
    Ambiguous = 4,
    WrongContract = 5,
    Cycle = 6,
    Unhooked = 7,
    Duplicate = 8,
    SharedSection = 9,
}
