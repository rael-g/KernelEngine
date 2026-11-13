using KernelEngine.Schedule;
using KernelEngine.Scheduler;

namespace KernelEngine;

/// <summary>
/// The standard schedules of an engine's world, added to its scheduler in the order they tick: startup,
/// pre-update, the fixed steps, update and shutdown.
/// </summary>
public sealed class EngineSchedules
{
    /// <summary>Runs once, before the first tick's other schedules.</summary>
    public required DefaultSchedule Startup { get; init; }

    /// <summary>Runs first in every tick.</summary>
    public required DefaultSchedule PreUpdate { get; init; }

    /// <summary>Runs once per fixed step.</summary>
    public required DefaultSchedule Fixed { get; init; }

    /// <summary>Runs after the fixed steps in every tick.</summary>
    public required DefaultSchedule Update { get; init; }

    /// <summary>Runs once, when the scheduler shuts down.</summary>
    public required DefaultSchedule Shutdown { get; init; }

    /// <summary>Adds the schedules to <paramref name="scheduler"/>, each at its cadence, in the order they tick.</summary>
    /// <param name="scheduler">The scheduler that runs them.</param>
    public void AddTo(DefaultScheduler scheduler)
    {
        scheduler.AddSchedule(Startup, SchedulerCadence.Startup);
        scheduler.AddSchedule(PreUpdate, SchedulerCadence.EveryTick);
        scheduler.AddSchedule(Fixed, SchedulerCadence.Fixed);
        scheduler.AddSchedule(Update, SchedulerCadence.EveryTick);
        scheduler.AddSchedule(Shutdown, SchedulerCadence.Shutdown);
    }
}
