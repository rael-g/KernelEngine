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
    public required KernelEngine.Schedule.Schedule Startup { get; init; }

    /// <summary>Runs first in every tick.</summary>
    public required KernelEngine.Schedule.Schedule PreUpdate { get; init; }

    /// <summary>Runs once per fixed step.</summary>
    public required KernelEngine.Schedule.Schedule Fixed { get; init; }

    /// <summary>Runs after the fixed steps in every tick.</summary>
    public required KernelEngine.Schedule.Schedule Update { get; init; }

    /// <summary>Runs once, when the scheduler shuts down.</summary>
    public required KernelEngine.Schedule.Schedule Shutdown { get; init; }

    /// <summary>Runs over the render world once per extraction; null when the engine has no render stage.</summary>
    public KernelEngine.Schedule.Schedule? Render { get; init; }

    /// <summary>Adds the schedules to <paramref name="scheduler"/>, each at its cadence, in the order they tick.</summary>
    /// <param name="scheduler">The scheduler that runs them.</param>
    public void AddTo(KernelEngine.Scheduler.Scheduler scheduler)
    {
        Add(scheduler, Startup, SchedulerCadence.Startup);
        Add(scheduler, PreUpdate, SchedulerCadence.EveryTick);
        Add(scheduler, Fixed, SchedulerCadence.Fixed);
        Add(scheduler, Update, SchedulerCadence.EveryTick);
        Add(scheduler, Shutdown, SchedulerCadence.Shutdown);
    }

    /// <summary>Attaches <paramref name="module"/> to these schedules and the standard <paramref name="sets"/> registered in them.</summary>
    /// <param name="module">The module whose systems join the schedules.</param>
    /// <param name="sets">The sets the schedules hold.</param>
    public unsafe void Attach(KernelEngine.Module.Module module, EngineSets sets) =>
        module.Attach((nint)((INativeSchedule)Startup).Native, (nint)((INativeSchedule)PreUpdate).Native, (nint)((INativeSchedule)Fixed).Native,
            (nint)((INativeSchedule)Update).Native, (nint)((INativeSchedule)Shutdown).Native, Render is null ? 0 : (nint)((INativeSchedule)Render).Native,
            sets.Startup, sets.PreUpdate, sets.FixedPreUpdate, sets.FixedUpdate, sets.FixedPostUpdate, sets.Update, sets.PostUpdate, sets.Shutdown,
            sets.RenderBegin, sets.RenderPrepare, sets.RenderQueue, sets.RenderSubmit);

    /// <summary>Adds <paramref name="extraction"/> to <paramref name="scheduler"/>, ticking every tick, run by its own native run slot, and <paramref name="render"/> after it.</summary>
    /// <param name="scheduler">The scheduler that runs them.</param>
    /// <param name="extraction">The extraction into the render world.</param>
    /// <param name="render">The schedule over the render world.</param>
    public static unsafe void AddRender(INativeScheduler scheduler, KernelEngine.Extraction.INativeExtraction extraction, INativeSchedule render)
    {
        var native = extraction.Native;
        var run = (delegate* unmanaged[Cdecl]<void*, float, KernelEngine.Completion.Native.ke_completion**, KernelEngine.Result.Native.Result>)native->run;
        NativeCall.ThrowIfFailed(scheduler.Native->add(scheduler.Native, run, native, SchedulerCadence.EveryTick), "ke_scheduler.add");
        Add(scheduler, render, SchedulerCadence.EveryTick);
    }

    /// <summary>Adds <paramref name="schedule"/> to <paramref name="scheduler"/> as an executable whose user is the schedule, run by its own native run slot.</summary>
    /// <param name="scheduler">The scheduler that runs it.</param>
    /// <param name="schedule">The schedule it runs.</param>
    /// <param name="cadence">When it runs.</param>
    public static unsafe void Add(INativeScheduler scheduler, INativeSchedule schedule, SchedulerCadence cadence)
    {
        var native = schedule.Native;
        var run = (delegate* unmanaged[Cdecl]<void*, float, KernelEngine.Completion.Native.ke_completion**, KernelEngine.Result.Native.Result>)native->run;
        NativeCall.ThrowIfFailed(scheduler.Native->add(scheduler.Native, run, native, cadence), "ke_scheduler.add");
    }
}
