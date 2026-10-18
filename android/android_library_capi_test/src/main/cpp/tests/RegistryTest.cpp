// The registration table and TryRelease (C ABI design part 1, 5.7, AC-6), on the sources of
// libntk.so compiled into this test library. The main-thread steps are tested end to end with
// the probe (ProbeTest.cpp).
#include <gtest/gtest.h>

#include <atomic>
#include <thread>
#include <vector>

#include "../TestSupport.h"
#include "Common/Registry.h"

namespace registry = nativetoolkit::registry;
using registry::State;

namespace {

void CountRelease(void* user_data) {
    static_cast<std::atomic<int>*>(user_data)->fetch_add(1);
}

}  // namespace

TEST(Registry, IdsAreNeverReused) {
    std::atomic<int> releases{0};
    uint64_t first = registry::Add(1, nullptr, &releases, CountRelease, nullptr);
    uint64_t second = registry::Add(1, nullptr, &releases, CountRelease, nullptr);
    EXPECT_NE(0u, first);
    EXPECT_LT(first, second);
    EXPECT_TRUE(registry::TryRelease(first, State::kActive));
    uint64_t third = registry::Add(1, nullptr, &releases, CountRelease, nullptr);
    EXPECT_LT(second, third);
    registry::TryRelease(second, State::kActive);
    registry::TryRelease(third, State::kActive);
    EXPECT_EQ(3, releases.load());
}

TEST(Registry, TryReleaseCallsReleaseOnceAndOnlyFromTheExpectedState) {
    std::atomic<int> releases{0};
    uint64_t id = registry::Add(1, nullptr, &releases, CountRelease, nullptr);
    EXPECT_EQ(State::kActive, registry::StateOf(id));
    EXPECT_FALSE(registry::TryRelease(id, State::kCancelRequested));
    EXPECT_EQ(0, releases.load());
    EXPECT_TRUE(registry::TryRelease(id, State::kActive));
    EXPECT_EQ(1, releases.load());
    EXPECT_FALSE(registry::TryRelease(id, State::kActive));
    EXPECT_EQ(State::kReleased, registry::StateOf(id));
    EXPECT_EQ(1, releases.load());
}

TEST(Registry, ACancelWhoseRemovalCannotBePostedRunsWhenTheMainThreadNextEnters) {
    // No ledger here, so no removal can be posted: it is queued, the state stays CANCEL_REQUESTED
    // (review v2, R-X1), and the main thread runs it the next time it enters for a registration.
    // The same with the real ledger and the main thread's other ways in is in ProbeTest.cpp.
    std::atomic<int> releases{0};
    uint64_t id = registry::Add(1, nullptr, &releases, CountRelease, nullptr);
    EXPECT_TRUE(registry::Cancel(id, {1}));
    EXPECT_EQ(State::kCancelRequested, registry::StateOf(id));
    EXPECT_FALSE(registry::Cancel(id, {1}));  // already on its way
    EXPECT_EQ(0, releases.load());
    bool delivered = false;
    ntktest::RunOnMain([&] {
        registry::DeliverOnMain(id, [&](registry::Registration&) { delivered = true; });
    });
    EXPECT_FALSE(delivered);
    EXPECT_EQ(1, releases.load());
    EXPECT_EQ(State::kReleased, registry::StateOf(id));
    EXPECT_FALSE(registry::Cancel(0xFFFFFFFFFFFFull, {1}));
}

TEST(Registry, ACancelOfAnotherKindChangesNothing) {
    // An id given to the wrong feature's cancel (review K-M7): not touched.
    std::atomic<int> releases{0};
    uint64_t id = registry::Add(1, nullptr, &releases, CountRelease, nullptr);
    EXPECT_FALSE(registry::Cancel(id, {2, 3}));
    EXPECT_EQ(State::kActive, registry::StateOf(id));
    EXPECT_TRUE(registry::TryRelease(id, State::kActive));
    EXPECT_EQ(1, releases.load());
}

TEST(Registry, RacingReleasesReleaseExactlyOnce) {
    for (int round = 0; round < 200; ++round) {
        std::atomic<int> releases{0};
        uint64_t id = registry::Add(1, nullptr, &releases, CountRelease, nullptr);
        std::atomic<bool> go{false};
        std::atomic<int> won{0};
        std::vector<std::thread> threads;
        for (int i = 0; i < 8; ++i) {
            threads.emplace_back([&, i] {
                while (!go.load()) {
                }
                if (i % 2 == 0) {
                    if (registry::TryRelease(id, State::kActive)) won.fetch_add(1);
                } else if (registry::Cancel(id, {1})) {
                    if (registry::TryRelease(id, State::kCancelRequested)) won.fetch_add(1);
                }
            });
        }
        go.store(true);
        for (std::thread& thread : threads) thread.join();
        // Either a direct release won, or the one Cancel that won released from CANCEL_REQUESTED
        // (its removal is queued, since this copy has no ledger, and finds nothing later).
        ASSERT_EQ(1, won.load()) << "round " << round;
        ASSERT_EQ(1, releases.load()) << "round " << round;
        ASSERT_EQ(State::kReleased, registry::StateOf(id));
    }
}

TEST(Registry, ARejectedCallIsReleasedAtOnceAndNullReleaseIsAllowed) {
    std::atomic<int> releases{0};
    registry::ReleaseRejected(CountRelease, &releases);
    EXPECT_EQ(1, releases.load());
    registry::ReleaseRejected(nullptr, &releases);
    uint64_t id = registry::Add(1, nullptr, nullptr, nullptr, nullptr);
    EXPECT_TRUE(registry::TryRelease(id, State::kActive));
}
