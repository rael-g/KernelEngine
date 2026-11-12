using KernelEngine.Scheduler;

namespace KernelEngine;

/// <summary>
/// The set every standard phase of the scheduler is registered with, for the systems that need no
/// other order; the phases tick in the order the properties are listed.
/// </summary>
public sealed class EngineSets
{
    /// <summary>The set of the phase that runs once, before the first tick's other phases.</summary>
    public required uint Startup { get; init; }

    /// <summary>The set of the phase that runs first in every tick.</summary>
    public required uint PreUpdate { get; init; }

    /// <summary>The set of the first fixed phase.</summary>
    public required uint FixedPreUpdate { get; init; }

    /// <summary>The set of the second fixed phase.</summary>
    public required uint FixedUpdate { get; init; }

    /// <summary>The set of the last fixed phase.</summary>
    public required uint FixedPostUpdate { get; init; }

    /// <summary>The set of the phase that runs after the fixed steps.</summary>
    public required uint Update { get; init; }

    /// <summary>The set of the phase that runs after the update.</summary>
    public required uint PostUpdate { get; init; }

    /// <summary>The set of the phase that runs last in every tick.</summary>
    public required uint Render { get; init; }

    /// <summary>The set of the phase that runs once, when the scheduler shuts down.</summary>
    public required uint Shutdown { get; init; }

    /// <summary>Registers the standard phases of <paramref name="scheduler"/>, each with a set of its name.</summary>
    /// <param name="scheduler">The scheduler the phases are registered with.</param>
    /// <returns>The set of each phase.</returns>
    public static EngineSets Register(DefaultScheduler scheduler)
    {
        uint Phase(string name, PhaseCadence cadence, bool pipelined = false) => scheduler.RegisterSet(name, scheduler.RegisterPhase(name, cadence, pipelined), []);
        return new EngineSets
        {
            Startup = Phase("startup", PhaseCadence.Startup),
            PreUpdate = Phase("pre_update", PhaseCadence.EveryTick),
            FixedPreUpdate = Phase("fixed_pre_update", PhaseCadence.Fixed),
            FixedUpdate = Phase("fixed_update", PhaseCadence.Fixed),
            FixedPostUpdate = Phase("fixed_post_update", PhaseCadence.Fixed),
            Update = Phase("update", PhaseCadence.EveryTick),
            PostUpdate = Phase("post_update", PhaseCadence.EveryTick),
            Render = Phase("render", PhaseCadence.EveryTick, pipelined: true),
            Shutdown = Phase("shutdown", PhaseCadence.Shutdown),
        };
    }
}
