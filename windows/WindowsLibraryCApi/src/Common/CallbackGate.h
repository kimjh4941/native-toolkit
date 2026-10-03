#pragma once
// The liveness flag of a handle whose callbacks must stop at _free (stage 5
// design 7.5.2).

#include <condition_variable>
#include <cstdint>
#include <map>
#include <mutex>
#include <thread>

namespace NativeToolkitC::Detail {

/**
 * @brief Lets callbacks through until the gate is shut, and waits for the
 *        ones running elsewhere when it is.
 * @details No lock is held while a callback runs. A callback that runs another
 *          callback of the same handle on the same thread (a write inside a
 *          callback that makes the OS ask for a deferred format, a modal loop)
 *          only adds to the count and never blocks. Shut() waits for calls on
 *          other threads, never for the ones on its own thread, so shutting
 *          from inside a callback does not deadlock; the C ABI forbids it all
 *          the same (design 1.3.5).
 */
class CallbackGate {
public:
    /// Runs callback unless the gate is shut. Returns whether it ran.
    template <class F>
    bool Run(F&& callback)
    {
        if (!Enter()) return false;
        struct Leaver {
            CallbackGate& gate;
            ~Leaver() { gate.Leave(); }
        } leaver{*this};
        callback();
        return true;
    }

    /// Shuts the gate: no callback starts after this returns, and every one
    /// running on another thread has finished.
    void Shut();

    bool IsOpen() const;

private:
    bool Enter();
    void Leave();

    mutable std::mutex                    mutex_;
    std::condition_variable               idle_;
    bool                                  open_ = true;
    uint32_t                              running_ = 0;
    std::map<std::thread::id, uint32_t>   runningOn_;
};

}  // namespace NativeToolkitC::Detail
