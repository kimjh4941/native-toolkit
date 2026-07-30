#include "pch.h"
#include "WindowsClipboardLifecycle.h"

void ClipboardLifecycle::Lease::Release()
{
    if (owner_)
    {
        owner_->ReleaseLease();
        owner_ = nullptr;
    }
}

std::optional<ClipboardLifecycle::Lease> ClipboardLifecycle::TryEnter()
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (closed_) return std::nullopt;
    ++inFlight_;
    return Lease(this);
}

void ClipboardLifecycle::ReleaseLease()
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (inFlight_ > 0) --inFlight_;
}

void ClipboardLifecycle::CloseAndReserveDrainWork(size_t drainCount)
{
    std::lock_guard<std::mutex> lock(mutex_);
    closed_ = true;
    drainWork_ += drainCount;
}

void ClipboardLifecycle::ReleaseDrainWork()
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (drainWork_ > 0) --drainWork_;
}

void ClipboardLifecycle::Reopen()
{
    std::lock_guard<std::mutex> lock(mutex_);
    closed_ = false;
    inFlight_ = 0;
    drainWork_ = 0;
}

bool ClipboardLifecycle::IsClosed() const
{
    std::lock_guard<std::mutex> lock(mutex_);
    return closed_;
}

bool ClipboardLifecycle::CanDestroy() const
{
    std::lock_guard<std::mutex> lock(mutex_);
    return closed_ && inFlight_ == 0 && drainWork_ == 0;
}
