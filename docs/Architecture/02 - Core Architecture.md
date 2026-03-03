# Architecture Vision: Core Architecture

## 1. Dependency Management
Kernel Engine follows a strict **Inversion of Control** model. Subsystems do not "reach out" to find their dependencies via service locators or global singletons.

Instead, all connections are wired by the host application during the creation of a system. This approach transforms the engine from a "black box" into a transparent graph of components, where data and dependency flow are easily traced and validated.

## 2. Explicit Memory Management
The engine treats memory as a first-class resource that must be explicitly managed per subsystem. By requiring an allocator for every major component, the architecture enables:
*   **Domain Isolation**: One subsystem's memory usage cannot silently impact another's.
*   **Custom Strategies**: Subsystems can employ optimal allocation patterns (e.g., fast frame-based arenas for temporary data vs. long-lived pools for assets).
*   **Observability**: Developers can monitor and limit memory usage per domain.

## 3. Deterministic Results
A core architectural invariant is that every operation must have a deterministic and explicit outcome.
*   **Failure as a Value**: Error states are returned as first-class values rather than using side-channel mechanisms like exceptions.
*   **Explicit Handling**: Callers are forced to acknowledge success or failure, leading to more robust and easier-to-debug systems.

## 4. Communication Architecture
While systems are functional units, they often need to communicate events without introducing direct coupling. The engine facilitates this through an **asynchronous messaging infrastructure**:
*   **Decoupled Events**: Systems broadcast messages to an abstract pipe.
*   **Anonymous Consumers**: Interested parties can react to events without any knowledge of the producer.
*   **Flow Control**: This mechanism ensures that high-frequency events (like input) don't create "wiring hell" between unrelated domains.
