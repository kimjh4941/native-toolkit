// Registrations and the one way they are released (C ABI design part 1, 5.7, AC-6, AC-17, AC-21).
//
// A registration is made ACTIVE with an id before Kotlin is called, and lives in one table (id to
// registration) guarded by a mutex. Kotlin gets only the id; its ledger (capi.jni.Ledger) is
// touched on the main thread only. release is called by TryRelease alone, after a successful
// compare-and-swap to RELEASED, outside the mutex. Once accepted, a registration is freed only on
// the main thread, so a pointer found on the main thread stays valid for that main message.
#pragma once

#include <jni.h>

#include <atomic>
#include <cstddef>
#include <cstdint>
#include <initializer_list>

#include "Classes.h"
#include "NativeToolkitC/Common.h"

namespace nativetoolkit::registry {

enum class State : int {
    kActive = 0,
    kCancelRequested = 1,
    kReleased = 2,
};

struct Registration;

// Completes an operation with its canceled value (the feature knows which).
using CancelCompletion = void (*)(Registration& registration);

struct Registration {
    uint64_t id = 0;
    int32_t kind = 0;                            // the ledger kind (capi.jni.Ledger)
    void* callback = nullptr;                    // the feature's callback; the feature casts it back
    void* user_data = nullptr;
    ntk_release_fn release = nullptr;
    CancelCompletion cancel_completion = nullptr;  // set for an operation with a completion
    std::atomic<int> state{static_cast<int>(State::kActive)};
    bool completed = false;                      // main thread only
    bool unposted = false;                       // its removal could not be posted; under the table mutex
};

// Makes an ACTIVE registration and puts it in the table. Returns its id (never 0), or 0 when out
// of memory, in which case nothing was kept and the caller releases.
uint64_t Add(int32_t kind, void* callback, void* user_data, ntk_release_fn release,
             CancelCompletion cancel_completion) noexcept;

// The one function that calls release (design 5.7): when the registration is in the table and
// its state moves from expected to RELEASED, takes it out, then outside the mutex calls release
// and frees it. Returns whether it did.
bool TryRelease(uint64_t id, State expected) noexcept;

// Calls release on the calling thread for a call rejected at the entry, before anything was
// registered (design 1.3).
void ReleaseRejected(ntk_release_fn release, void* user_data) noexcept;

// Cancels or removes from any thread, without waiting: ACTIVE becomes CANCEL_REQUESTED, and the
// removal is posted to the main thread. Does nothing for an id that is not ACTIVE (completed,
// released, unknown) or not of one of kinds (an id of another feature's registration, given by
// mistake). A removal that cannot be posted (attaching or Kotlin failed) is marked on the
// registration instead, and the main thread runs it the next time it enters the C ABI
// (DrainUnpostedOnMain); nothing is allocated for it. The state never goes back to ACTIVE, since the
// main thread may already have acted on CANCEL_REQUESTED (review v2, R-X1). There is no bound on
// when that next entry comes: a removal waits for the next completion, event or insertion of any
// registration (review v3, S-M1). Returns whether it moved the registration, that is, whether a
// removal is on its way.
bool Cancel(uint64_t id, std::initializer_list<int32_t> kinds) noexcept;

// Main thread only: runs the removals that Cancel could not post, until none is left (a removal's
// canceled completion or release may cancel another). Every way the main thread enters the C ABI for
// a registration calls it first (the removal, the completion, the delivery, the insertion's check),
// so app code (canceled completions, releases) may run inside those calls (review v3, S-M5). Does
// nothing when called again from inside a removal it runs.
void DrainUnpostedOnMain() noexcept;

// Debug probe only: the next removal Cancel posts fails, as if Kotlin could not be called.
void FailNextRemovePost() noexcept;

// The state of a registration, or kReleased when it is not in the table.
State StateOf(uint64_t id) noexcept;

// Main thread only: the registration while it is in the table.
Registration* FindOnMain(uint64_t id) noexcept;

// Main thread only: the completion of an operation (design 5.7, the 完了 row). invoke calls the
// feature's callback with the result; a cancel requested meanwhile turns it into the canceled
// completion, and the result is dropped.
template <class Invoke>
void CompleteOnMain(uint64_t id, Invoke&& invoke) noexcept {
    DrainUnpostedOnMain();
    Registration* registration = FindOnMain(id);
    if (registration == nullptr) return;
    auto state = static_cast<State>(registration->state.load());
    if (state == State::kActive) {
        if (!registration->completed) {
            registration->completed = true;
            invoke(*registration);
        }
        // Fails when the callback, or another thread meanwhile, asked to cancel: the removal
        // that the cancel posted (or queued) releases it.
        TryRelease(id, State::kActive);
    } else if (state == State::kCancelRequested) {
        if (!registration->completed && registration->cancel_completion != nullptr) {
            registration->completed = true;
            registration->cancel_completion(*registration);
        }
        TryRelease(id, State::kCancelRequested);
    }
}

// Main thread only: delivers an event to a registration that is still ACTIVE (design 5.7, the
// 配送 row). A removal from the main thread therefore stops deliveries at once.
template <class Invoke>
void DeliverOnMain(uint64_t id, Invoke&& invoke) noexcept {
    DrainUnpostedOnMain();
    Registration* registration = FindOnMain(id);
    if (registration != nullptr && registration->state.load() == static_cast<int>(State::kActive)) {
        invoke(*registration);
    }
}

// The number of registrations in the table, for the tests.
size_t Count() noexcept;

// capi.jni.Ledger: its natives and the method that posts a removal.
classes::ClassSpec LedgerClassSpec();

}  // namespace nativetoolkit::registry
