#ifndef KERNEL_ENGINE_ASSEMBLY_ASSEMBLY_H_
#define KERNEL_ENGINE_ASSEMBLY_ASSEMBLY_H_

#include <kernel_engine/logger/log_callback.h>
#include <kernel_engine/part/part.h>
#include <kernel_engine/result/result.h>

#ifdef __cplusplus
extern "C" {
#endif

/// What resolve returns when the composition cannot be assembled.
#define KE_RESULT_ASSEMBLY_UNRESOLVED KE_RESULT_CODE(KE_RESULT_DOMAIN_ASSEMBLY, 1)

/// Why a composition cannot be assembled.
typedef enum ke_assembly_failure {
    /// An instance names a part no one added.
    KE_ASSEMBLY_FAILURE_UNKNOWN_PART = 1,
    /// A binding, an order or a default names an instance, a slot or a hook that does not exist.
    KE_ASSEMBLY_FAILURE_UNKNOWN_NAME = 2,
    /// A slot that takes one instance has no candidate.
    KE_ASSEMBLY_FAILURE_UNSATISFIED = 3,
    /// A slot that takes one instance has more than one candidate and the composition chose none.
    KE_ASSEMBLY_FAILURE_AMBIGUOUS = 4,
    /// A bound instance does not provide the slot's contract.
    KE_ASSEMBLY_FAILURE_WRONG_CONTRACT = 5,
    /// The instances need each other, or the orders of a slot or of a schedule's sets contradict each other.
    KE_ASSEMBLY_FAILURE_CYCLE = 6,
    /// A hook is bound to no schedule, or to a set its schedule does not have.
    KE_ASSEMBLY_FAILURE_UNHOOKED = 7,
    /// A part, an instance or an external contract is given a name already taken.
    KE_ASSEMBLY_FAILURE_DUPLICATE = 8,
    /// Instances of different parts are created with the same section, whose keys one of them would refuse.
    KE_ASSEMBLY_FAILURE_SHARED_SECTION = 9,
} ke_assembly_failure;

/// Receives one reason a composition cannot be assembled.
/// @param ctx [context] Forwarded from resolve.
/// @param failure The reason.
/// @param instance [borrowed,utf8,optional] The instance it concerns; valid only during the call.
/// @param name [borrowed,utf8,optional] The slot, hook, part or set it concerns; valid only during the call.
/// @param detail [borrowed,utf8] A line naming what was found, as the candidates; valid only during the call.
typedef void (*ke_assembly_report_fn)(void *ctx, ke_assembly_failure failure, const char *instance, const char *name,
                                      const char *detail);

/// [interface] Assembles instances of parts from a composition: which instances exist, of which part, with which
/// section of settings, and which instance each slot and hook is bound to. Nothing is created before the whole
/// composition resolves. Every name is copied. Gathering records what it is given and checks nothing: every
/// mistake in it, as a name taken twice or one nothing declares, is reported by resolve, with the others.
typedef struct ke_assembly {
    void *handle;

    /// Sends every line the parts' libraries log to @p log: resolve calls each distinct log setter of the parts once,
    /// before anything is created. Without it they log to stderr.
    /// @param log [callback] Receives each line, on whichever thread logged; must outlive the assembly.
    /// @param log_ctx [context] Handed to @p log unchanged.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p log; KE_RESULT_NOT_SUPPORTED after resolve.
    ke_result (*route_log)(struct ke_assembly *self, ke_log_callback log, void *log_ctx);

    /// Makes @p part available to instances.
    /// @param part [borrowed] Must outlive the assembly.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p part; KE_RESULT_NOT_SUPPORTED after resolve;
    ///         KE_RESULT_OUT_OF_MEMORY.
    ke_result (*add_part)(struct ke_assembly *self, const ke_part *part);

    /// Declares the instance @p name of the part @p part, created with the section @p section of the configuration.
    /// @param name [utf8] Unique among the instances.
    /// @param part [utf8] A part's name.
    /// @param section [utf8,optional] A section of the configuration; NULL creates the instance with empty settings.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null @p name or @p part; KE_RESULT_NOT_SUPPORTED after
    ///         resolve; KE_RESULT_OUT_OF_MEMORY.
    ke_result (*add_instance)(struct ke_assembly *self, const char *name, const char *part, const char *section);

    /// Declares that the instance @p name, made by someone else, provides @p contract as @p instance; called once per
    /// contract it provides. Never destroyed by the assembly.
    /// @param name [utf8] No instance of a part has it.
    /// @param contract [utf8] The contract @p instance is the vtable of.
    /// @param instance [borrowed] Must outlive the assembly.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument; KE_RESULT_NOT_SUPPORTED after resolve;
    ///         KE_RESULT_OUT_OF_MEMORY.
    ke_result (*add_external)(struct ke_assembly *self, const char *name, const char *contract, void *instance);

    /// Binds the slot @p slot of @p instance to @p target; a slot that takes many is bound once per target.
    /// @param instance [utf8]
    /// @param slot [utf8]
    /// @param target [utf8] An instance's name.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument; KE_RESULT_NOT_SUPPORTED after resolve;
    ///         KE_RESULT_OUT_OF_MEMORY.
    ke_result (*bind)(struct ke_assembly *self, const char *instance, const char *slot, const char *target);

    /// Binds the hook @p hook of @p instance to the set @p set of the schedule instance @p schedule. A hook nothing
    /// binds joins the only schedule that has its default set.
    /// @param instance [utf8]
    /// @param hook [utf8]
    /// @param schedule [utf8] An instance providing ke_schedule.
    /// @param set [utf8,optional] NULL takes the hook's default set.
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument other than @p set;
    ///         KE_RESULT_NOT_SUPPORTED after resolve; KE_RESULT_OUT_OF_MEMORY.
    ke_result (*hook)(struct ke_assembly *self, const char *instance, const char *hook, const char *schedule,
                      const char *set);

    /// Orders two instances bound to the slot @p slot of @p instance: @p first comes before @p then. Instances of a
    /// slot with no order between them come in no guaranteed order. With no @p slot, orders two instances bound to
    /// slots of @p instance, the same or different ones, by the positions the part receives.
    /// @param instance [utf8]
    /// @param slot [utf8,optional] NULL orders across the slots of @p instance.
    /// @param first [utf8]
    /// @param then [utf8]
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument other than @p slot; KE_RESULT_NOT_SUPPORTED
    ///         after resolve;
    ///         KE_RESULT_OUT_OF_MEMORY.
    ke_result (*order)(struct ke_assembly *self, const char *instance, const char *slot, const char *first,
                       const char *then);

    /// Introduces the set @p name in the schedule instance @p schedule.
    /// @param schedule [utf8]
    /// @param name [utf8]
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument; KE_RESULT_NOT_SUPPORTED after resolve;
    ///         KE_RESULT_OUT_OF_MEMORY.
    ke_result (*add_set)(struct ke_assembly *self, const char *schedule, const char *name);

    /// Orders two sets of the schedule instance @p schedule: @p first runs before @p then.
    /// @param schedule [utf8]
    /// @param first [utf8]
    /// @param then [utf8]
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument; KE_RESULT_NOT_SUPPORTED after resolve;
    ///         KE_RESULT_OUT_OF_MEMORY.
    ke_result (*order_set)(struct ke_assembly *self, const char *schedule, const char *first, const char *then);

    /// Names the instance every slot of @p contract the composition binds nothing to takes.
    /// @param contract [utf8]
    /// @param instance [utf8]
    /// @return KE_OK; KE_RESULT_INVALID_ARGUMENT for a null argument; KE_RESULT_NOT_SUPPORTED after resolve;
    ///         KE_RESULT_OUT_OF_MEMORY.
    ke_result (*set_default)(struct ke_assembly *self, const char *contract, const char *instance);

    /// Resolves the whole composition, creating nothing. A slot that takes one instance, or none, takes the one bound
    /// to it, else the default of its contract, else the only instance that provides it; a slot that takes many takes
    /// exactly the instances bound to it, none when nothing is. Every reason it cannot be assembled is reported.
    /// @param report [closure:ctx,optional] Receives each reason; NULL reports none.
    /// @param ctx [context] Handed to @p report unchanged.
    /// @return KE_OK; KE_RESULT_ASSEMBLY_UNRESOLVED when any reason was found; KE_RESULT_NOT_SUPPORTED when already
    ///         resolved.
    ke_result (*resolve)(struct ke_assembly *self, ke_assembly_report_fn report, void *ctx);

    /// Creates the instances whose slots are ready, each after every instance it is bound to became usable,
    /// pumping the instances already made while one is not.
    /// @return KE_OK once every instance is made and usable; KE_RESULT_PENDING while one is becoming usable;
    ///         KE_RESULT_NOT_SUPPORTED before resolve; the code an instance failed to be created or to become usable
    ///         with, every instance made so far destroyed in reverse.
    ke_result (*advance)(struct ke_assembly *self);

    /// Gives the instance @p name as the vtable of @p contract.
    /// @param name [utf8]
    /// @param contract [utf8] One of the contracts the instance provides.
    /// @param out_instance [out] Receives the vtable.
    /// @return KE_OK; KE_RESULT_NOT_FOUND when no instance has that name, it does not provide @p contract or it is
    ///         not made yet; KE_RESULT_INVALID_ARGUMENT for a null argument.
    ke_result (*get)(struct ke_assembly *self, const char *name, const char *contract, void **out_instance);
} ke_assembly;

/// [owner] Destroying it destroys every instance it made, in the reverse of the order it made them.
typedef struct ke_assembly_handle {
    ke_assembly *ref;
    void (*destroy)(ke_assembly *self);
} ke_assembly_handle;

#ifdef __cplusplus
}
#endif

#endif
