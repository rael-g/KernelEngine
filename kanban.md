# Kernel Engine — Kanban

## done

### Core C Kernel
  - tags: [Core, Architecture]
  - priority: high
  - workload: Hard
  - defaultExpanded: false
  - steps:
      - [x] Implement minimal orchestration layer
      - [x] Remove dynamic context dependency
      - [x] Define stable C API boundaries
    ```md
    The core of the engine, providing the foundational logic for system management and lifecycle orchestration without unnecessary bloat.
    ```

### Inversion of Control
  - tags: [Core, Architecture, Patterns]
  - priority: high
  - workload: Medium
  - defaultExpanded: false
  - steps:
      - [x] Implement explicit dependency injection via descriptors
      - [x] Remove service discovery mechanisms
    ```md
    Ensures that all systems and services receive their dependencies at creation time, leading to a more predictable and testable architecture.
    ```

### Deterministic Error Handling
  - tags: [Core, Standards]
  - priority: high
  - workload: Normal
  - defaultExpanded: false
  - steps:
      - [x] Standardize all APIs to return ke_result
      - [x] Implement error propagation across systems
    ```md
    Enforces explicit handling of success and failure states, avoiding hidden exceptions or undefined behavior.
    ```

### Memory Abstraction
  - tags: [Core, Performance]
  - priority: high
  - workload: Medium
  - defaultExpanded: false
  - steps:
      - [x] Implement Malloc allocator
      - [x] Implement Arena allocator
      - [x] Integrate ke_allocator into all core domains
    ```md
    Provides a uniform interface for memory operations, enabling custom allocation strategies per subsystem.
    ```

### Logging System
  - tags: [Infrastructure, Utilities]
  - priority: medium
  - workload: Normal
  - defaultExpanded: false
  - steps:
      - [x] Implement multi-sink logger
      - [x] Implement domain-based tagging
    ```md
    Centralized logging capability for diagnostics and debugging across different engine domains.
    ```

### Messaging Pipe
  - tags: [Infrastructure, Communication]
  - priority: medium
  - workload: Medium
  - defaultExpanded: false
  - steps:
      - [x] Implement asynchronous broadcast/receive system
      - [x] Support decoupled communication between systems
    ```md
    A fundamental mechanism for asynchronous data exchange, allowing systems to communicate without direct functional coupling.
    ```

### Windowing Domain
  - tags: [Platform, Plugin]
  - priority: high
  - workload: Medium
  - defaultExpanded: false
  - steps:
      - [x] Implement GLFW-based window system
      - [x] Support basic window lifecycle and event polling
    ```md
    Abstraction for OS-level window management and interaction.
    ```

### Rendering Domain
  - tags: [Render, Plugin]
  - priority: highest
  - workload: Hard
  - defaultExpanded: false
  - steps:
      - [x] Implement BGFX-based render system
      - [x] Implement manual shader loading from binaries
    ```md
    The primary rendering subsystem, responsible for pushing commands to the GPU via the BGFX abstraction.
    ```

### Input Domain
  - tags: [Platform, Input]
  - priority: high
  - workload: Medium
  - defaultExpanded: false
  - steps:
      - [x] Implement state-tracking system
      - [x] Map message pipe events to input states
    ```md
    Unified input management for keyboard and mouse, driven by events from the message pipe.
    ```

### Shader Compilation
  - tags: [Render, Tooling]
  - priority: medium
  - workload: Normal
  - defaultExpanded: false
  - steps:
      - [x] Implement standalone plugin for shaderc
      - [x] Support cross-platform shader compilation at runtime/build-time
    ```md
    Tooling for converting BGFX shader source files into engine-ready binary formats.
    ```

### Code Quality
  - tags: [CI/CD, Standards]
  - priority: high
  - workload: Normal
  - defaultExpanded: false
  - steps:
      - [x] Integrate clang-format into CMake
      - [x] Integrate clang-tidy into CMake
      - [x] Refine quality rules for C/C++ compatibility
    ```md
    Automated tools to ensure the codebase remains clean, consistent, and follows defined engineering standards.
    ```

## backlog

### Job System
  - tags: [Infrastructure, Performance]
  - priority: highest
  - workload: Hard
  - defaultExpanded: true
  - steps:
      - [ ] Implement Worker Thread Pool
      - [ ] Implement Lock-free Job Queue
      - [ ] Implement Job Dependencies/Counter
      - [ ] Create C API for Job submission
    ```md
    A high-performance task orchestration system to enable massive parallelism across engine subsystems.
    ```

### C# Interop
  - tags: [Scripting, Interop]
  - priority: high
  - workload: Medium
  - defaultExpanded: true
  - steps:
      - [ ] Create KernelEngine.Native C# library
      - [ ] Map Core C structs and function pointers to P/Invoke
      - [ ] Implement Managed-to-Native lifecycle bridge
    ```md
    The bridge between the native performance of the C kernel and the high-level expressiveness of C#.
    ```

## future

### World & Scene Model
  - tags: [Scene, Core]
  - priority: high
  - workload: Hard
  - defaultExpanded: false
  - steps:
      - [ ] Implement Node-based Hierarchy
      - [ ] Implement Entity-Component-System (ECS)
      - [ ] Integrate ECS with Rendering
    ```md
    The high-level data model for representing and updating objects in the simulated world.
    ```

### Physics Integration
  - tags: [Simulation, Physics]
  - priority: medium
  - workload: Hard
  - defaultExpanded: false
  - steps:
      - [ ] Implement Box2D/Jolt System Plugin
      - [ ] Map collision events to Message Pipe
    ```md
    Integration of external physics engines to handle rigid body dynamics and collision detection.
    ```

### Asset Management
  - tags: [Assets, Infrastructure]
  - priority: medium
  - workload: Medium
  - defaultExpanded: false
  - steps:
      - [ ] Implement Resource Reference Counting
      - [ ] Implement Async Loading via Job System
      - [ ] Implement Central Asset Cache
    ```md
    A robust system for loading, managing, and caching game assets like textures, models, and sounds.
    ```

### Serialization & Persistence
  - tags: [Data, Serialization]
  - priority: low
  - workload: Medium
  - defaultExpanded: false
  - steps:
      - [ ] Define JSON/Binary scene formats
      - [ ] Implement Prefab/Blueprint system
    ```md
    Mechanisms for saving and loading world states, configurations, and object templates.
    ```

### Editor Foundation
  - tags: [Tooling, Editor]
  - priority: lowest
  - workload: Hard
  - defaultExpanded: false
  - steps:
      - [ ] Implement ImGui-based debug overlay
      - [ ] Create Editor Interface for system inspection
      - [ ] Implement System/Shader Hot-Reloading
    ```md
    The foundation for building visual tools to inspect, modify, and develop game worlds in real-time.
    ```
