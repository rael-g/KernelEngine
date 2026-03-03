# Architecture Vision: Engine Lifecycle & Systems

## 1. System Orchestration
The Kernel's primary role is to drive the lifecycle of its attached systems. This orchestration is strictly deterministic, ensuring that systems transition through distinct states in a predictable sequence.

## 2. Conceptual Lifecycle Phases

### 2.1 Registration
In this phase, the host application informs the Kernel about which systems will participate in the runtime. This is where the initial composition of the engine is defined.

### 2.2 Preparation (Readiness)
Once a system is registered, it must prepare its internal resources. Because all dependencies were provided during creation, the system has everything it needs to reach a "ready" state. The Kernel ensures that initialization happens in a controlled order.

### 2.3 The Execution Cycle (The Tick)
This is the steady-state of the engine. The Kernel repeatedly invokes the execution logic of all active systems. 
*   **Consistency**: Every system receives standardized data about the current execution step (time, frame index, etc.).
*   **Independence**: Systems perform their domain logic in isolation, interacting only through the established communication channels.

### 2.4 Controlled Disposal
When the engine is requested to stop, it performs a graceful shutdown. Systems are disposed of in the reverse order of their registration (LIFO), ensuring that any cross-system resource dependencies are handled safely.

## 3. Frame Context
The execution cycle is centered around the concept of a **Frame**. This is a discrete snapshot of time and state that ensures all systems are synchronized and working towards the same simulation target.
