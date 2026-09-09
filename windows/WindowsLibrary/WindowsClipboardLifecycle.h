/**
 * @file WindowsClipboardLifecycle.h
 * @brief Unified in-flight/closing state shared by request coroutines, history
 *        event callbacks and any-thread synchronous Bridge calls.
 * @details
 *  A single instance is owned by the Manager and referenced by the history
 *  coordinator. TryEnter()/CloseAndReserveDrainWork()/CanDestroy() are all
 *  guarded by the same mutex so that "may I still start work" and "is
 *  shutdown complete" can never race each other.
 */
#pragma once

#include <mutex>
#include <optional>

class ClipboardLifecycle
{
public:
    class Lease
    {
    public:
        Lease() = default;
        ~Lease() { Release(); }
        Lease(Lease&& other) noexcept : owner_(other.owner_) { other.owner_ = nullptr; }
        Lease& operator=(Lease&& other) noexcept
        {
            if (this != &other) { Release(); owner_ = other.owner_; other.owner_ = nullptr; }
            return *this;
        }
        Lease(const Lease&) = delete;
        Lease& operator=(const Lease&) = delete;

    private:
        friend class ClipboardLifecycle;
        explicit Lease(ClipboardLifecycle* owner) : owner_(owner) {}
        void Release();
        ClipboardLifecycle* owner_ = nullptr;
    };

    // Fails (returns nullopt) once Close has been called. Covers request
    // coroutines, history event callbacks and any-thread synchronous calls.
    std::optional<Lease> TryEnter();

    // Closes the gate and reserves `drainCount` units of additional closing
    // work (queued drain callbacks not yet delivered) in one atomic step.
    // Safe to call more than once; each call adds to the reservation.
    void CloseAndReserveDrainWork(size_t drainCount);
    void ReleaseDrainWork(); // once per delivered drain callback

    // Reopens the gate after a fully-completed shutdown, so the manager can
    // be initialized again from the same process.
    void Reopen();

    bool IsClosed() const;
    bool CanDestroy() const; // closed_ && inFlight_ == 0 && drainWork_ == 0

private:
    friend class Lease;
    void ReleaseLease();

    mutable std::mutex mutex_;
    bool   closed_ = false;
    int    inFlight_ = 0;
    size_t drainWork_ = 0;
};
