namespace KernelEngine;

/// <summary>
/// The standard sets, each in one of the <see cref="EngineSchedules"/>, for the systems that need no other order.
/// </summary>
public sealed class EngineSets
{
    /// <summary>The set of the startup schedule.</summary>
    public required uint Startup { get; init; }

    /// <summary>The set of the pre-update schedule.</summary>
    public required uint PreUpdate { get; init; }

    /// <summary>The first set of the fixed schedule.</summary>
    public required uint FixedPreUpdate { get; init; }

    /// <summary>The set of the fixed schedule after <see cref="FixedPreUpdate"/>.</summary>
    public required uint FixedUpdate { get; init; }

    /// <summary>The set of the fixed schedule after <see cref="FixedUpdate"/>.</summary>
    public required uint FixedPostUpdate { get; init; }

    /// <summary>The first set of the update schedule.</summary>
    public required uint Update { get; init; }

    /// <summary>The set of the update schedule after <see cref="Update"/>.</summary>
    public required uint PostUpdate { get; init; }

    /// <summary>The set of the shutdown schedule.</summary>
    public required uint Shutdown { get; init; }

    /// <summary>Registers the standard sets in <paramref name="schedules"/>.</summary>
    /// <param name="schedules">The schedules the sets are registered in.</param>
    /// <returns>The id of each set.</returns>
    public static EngineSets Register(EngineSchedules schedules)
    {
        var fixedPre = schedules.Fixed.RegisterSet("fixed_pre_update", []);
        var fixedUpdate = schedules.Fixed.RegisterSet("fixed_update", [fixedPre]);
        var update = schedules.Update.RegisterSet("update", []);
        return new EngineSets
        {
            Startup = schedules.Startup.RegisterSet("startup", []),
            PreUpdate = schedules.PreUpdate.RegisterSet("pre_update", []),
            FixedPreUpdate = fixedPre,
            FixedUpdate = fixedUpdate,
            FixedPostUpdate = schedules.Fixed.RegisterSet("fixed_post_update", [fixedUpdate]),
            Update = update,
            PostUpdate = schedules.Update.RegisterSet("post_update", [update]),
            Shutdown = schedules.Shutdown.RegisterSet("shutdown", []),
        };
    }
}
