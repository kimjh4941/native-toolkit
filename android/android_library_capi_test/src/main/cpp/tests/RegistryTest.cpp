// The registration table and TryRelease (C ABI design part 1, 5.7, AC-6), on the sources of
// libntk.so compiled into this test library. The main-thread steps are tested end to end with
// the probe (ProbeTest.cpp).
#include <gtest/gtest.h>

#include <atomic>
#include <thread>
#include <vector>

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

TEST(Registry, CancelMovesActiveToCancelRequestedOnce) {
    std::atomic<int> releases{0};
    uint64_t id = registry::Add(1, nullptr, &releases, CountRelease, nullptr);
    // No ledger here, so the removal is not posted; the state still moves.
    EXPECT_TRUE(registry::Cancel(id));
    EXPECT_EQ(State::kCancelRequested, registry::StateOf(id));
    EXPECT_FALSE(registry::Cancel(id));
    EXPECT_FALSE(registry::TryRelease(id, State::kActive));
    EXPECT_TRUE(registry::TryRelease(id, State::kCancelRequested));
    EXPECT_EQ(1, releases.load());
    EXPECT_FALSE(registry::Cancel(id));
    EXPECT_FALSE(registry::Cancel(0xFFFFFFFFFFFFull));
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
                } else if (registry::Cancel(id)) {
                    if (registry::TryRelease(id, State::kCancelRequested)) won.fetch_add(1);
                }
            });
        }
        go.store(true);
        for (std::thread& thread : threads) thread.join();
        // Either a direct release won, or the one Cancel that won released from CANCEL_REQUESTED.
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
