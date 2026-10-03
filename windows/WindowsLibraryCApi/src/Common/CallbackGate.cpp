// The liveness flag of a handle whose callbacks must stop at _free (stage 5
// design 7.5.2).

#include "Common/CallbackGate.h"

namespace NativeToolkitC::Detail {

bool CallbackGate::Enter()
{
    std::lock_guard<std::mutex> lock(mutex_);
    if (!open_) return false;
    ++running_;
    ++runningOn_[std::this_thread::get_id()];
    return true;
}

void CallbackGate::Leave()
{
    {
        std::lock_guard<std::mutex> lock(mutex_);
        --running_;
        const auto it = runningOn_.find(std::this_thread::get_id());
        if (it != runningOn_.end() && --it->second == 0) runningOn_.erase(it);
    }
    idle_.notify_all();
}

void CallbackGate::Shut()
{
    std::unique_lock<std::mutex> lock(mutex_);
    open_ = false;
    const auto self = std::this_thread::get_id();
    idle_.wait(lock, [&] {
        const auto it = runningOn_.find(self);
        const uint32_t mine = it == runningOn_.end() ? 0 : it->second;
        return running_ == mine;
    });
}

bool CallbackGate::IsOpen() const
{
    std::lock_guard<std::mutex> lock(mutex_);
    return open_;
}

}  // namespace NativeToolkitC::Detail
