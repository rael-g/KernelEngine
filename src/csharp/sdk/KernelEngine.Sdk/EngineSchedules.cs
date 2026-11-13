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
        Add(scheduler, Startup, SchedulerCadence.Startup);
        Add(scheduler, PreUpdate, SchedulerCadence.EveryTick);
        Add(scheduler, Fixed, SchedulerCadence.Fixed);
        Add(scheduler, Update, SchedulerCadence.EveryTick);
        Add(scheduler, Shutdown, SchedulerCadence.Shutdown);
    }

    /// <summary>Adds <paramref name="schedule"/> to <paramref name="scheduler"/> as an executable whose user is the schedule, run by its own native run slot.</summary>
    /// <param name="scheduler">The scheduler that runs it.</param>
    /// <param name="schedule">The schedule it runs.</param>
    /// <param name="cadence">When it runs.</param>
    public static unsafe void Add(INativeScheduler scheduler, INativeSchedule schedule, SchedulerCadence cadence)
    {
        var native = schedule.Native;
        var run = (delegate* unmanaged[Cdecl]<void*, float, KernelEngine.Completion.Native.ke_completion**, KernelEngine.Result.Native.Result>)native->run;
        NativeResults.ThrowIfFailed(scheduler.Native->add(scheduler.Native, run, native, cadence), "ke_scheduler.add");
    }
}
