// Release and completion exactly once, end to end (C ABI design part 1, 1.3, 5.7 and chapter 6):
// the probe operation and event of debug builds go through Accept, the registry, the Kotlin
// ledger and the main thread as the features do.
#include <gtest/gtest.h>

#include <unistd.h>

#include <atomic>
#include <thread>

#include "../TestSupport.h"
#include "../ntk_debug_probe.h"

using ntktest::Record;
using ntktest::Leaked;
using ntktest::Recorder;

namespace {

constexpr int32_t kNone = 0;
constexpr int32_t kInvalidParameter = 1;
constexpr int32_t kUnknown = 4;
constexpr int32_t kCanceled = 6;

// Every case ends with nothing left in the table or the ledger.
class Probe : public testing::Test {
protected:
    void TearDown() override {
        ntktest::DrainMain();
        EXPECT_EQ(0u, ntk_debug_probe_registrations());
        EXPECT_EQ(0, ntktest::LedgerSize());
    }
};

std::vector<std::string> Names(const std::vector<Record>& records) {
    std::vector<std::string> names;
    for (const Record& record : records) names.push_back(record.what);
    return names;
}

}  // namespace

TEST_F(Probe, ARejectedCallReleasesOnTheCallingThreadAndNeverCompletes) {
    Recorder& recorder = Leaked<Recorder>();
    uint64_t id = 99;
    EXPECT_EQ(kInvalidParameter, ntk_debug_probe_start(nullptr, &recorder, Recorder::Release, &id));
    EXPECT_EQ(0u, id);
    EXPECT_EQ(kInvalidParameter, ntk_debug_probe_start(Recorder::Done, &recorder, Recorder::Release, nullptr));
    // Both releases already ran, before the calls returned, on this thread.
    std::vector<Record> records = recorder.Records();
    ASSERT_EQ(2u, records.size());
    for (const Record& record : records) {
        EXPECT_EQ("release", record.what);
        EXPECT_EQ(gettid(), record.thread);
    }
    ntktest::DrainMain();
    EXPECT_EQ(0u, recorder.Count("done"));
}

TEST_F(Probe, AFailedPostReleasesOnTheCallingThreadAndNeverCompletes) {
    Recorder& recorder = Leaked<Recorder>();
    uint64_t id = 99;
    ntk_debug_probe_fail_next_post();
    EXPECT_EQ(kUnknown, ntk_debug_probe_start(Recorder::Done, &recorder, Recorder::Release, &id));
    EXPECT_EQ(0u, id);
    std::vector<Record> records = recorder.Records();
    ASSERT_EQ(1u, records.size());
    EXPECT_EQ("release", records[0].what);
    EXPECT_EQ(gettid(), records[0].thread);
    ntktest::DrainMain();
    EXPECT_EQ(0u, recorder.Count("done"));
}

TEST_F(Probe, ACompletionComesOnceOnMainThenTheRelease) {
    Recorder& recorder = Leaked<Recorder>();
    uint64_t id = 0;
    ASSERT_EQ(kNone, ntk_debug_probe_start(Recorder::Done, &recorder, Recorder::Release, &id));
    EXPECT_NE(0u, id);
    ASSERT_EQ(kNone, ntk_debug_probe_finish(id, 42));
    ASSERT_TRUE(recorder.WaitFor("release", 1));
    // A second result and a late cancel change nothing.
    ntk_debug_probe_finish(id, 43);
    ntk_debug_probe_cancel(id);
    ntktest::DrainMain();
    std::vector<Record> records = recorder.Records();
    ASSERT_EQ((std::vector<std::string>{"done", "release"}), Names(records));
    EXPECT_EQ(kNone, records[0].error);
    EXPECT_EQ(42, records[0].value);
    EXPECT_TRUE(records[0].on_main);
    EXPECT_TRUE(records[1].on_main);
}

TEST_F(Probe, FromTheMainThreadTheCompletionComesAfterTheCallReturns) {
    Recorder& recorder = Leaked<Recorder>();
    ntktest::RunOnMain([&] {
        uint64_t id = 0;
        ASSERT_EQ(kNone, ntk_debug_probe_start(Recorder::Done, &recorder, Recorder::Release, &id));
        ASSERT_EQ(kNone, ntk_debug_probe_finish(id, 1));
        recorder.Add({"returned"});
    });
    ASSERT_TRUE(recorder.WaitFor("release", 1));
    EXPECT_EQ((std::vector<std::string>{"returned", "done", "release"}), Names(recorder.Records()));
}

TEST_F(Probe, StartAndFinishRightAwayOffMainCompleteOnce) {
    for (int round = 0; round < 100; ++round) {
        Recorder& recorder = Leaked<Recorder>();
        uint64_t id = 0;
        ASSERT_EQ(kNone, ntk_debug_probe_start(Recorder::Done, &recorder, Recorder::Release, &id));
        ASSERT_EQ(kNone, ntk_debug_probe_finish(id, round));
        ASSERT_TRUE(recorder.WaitFor("release", 1)) << "round " << round;
        ntktest::DrainMain();
        ASSERT_EQ((std::vector<std::string>{"done", "release"}), Names(recorder.Records())) << "round " << round;
    }
}

TEST_F(Probe, ACancelRightAfterAcceptingCompletesCanceledOnce) {
    for (int round = 0; round < 100; ++round) {
        Recorder& recorder = Leaked<Recorder>();
        uint64_t id = 0;
        ASSERT_EQ(kNone, ntk_debug_probe_start(Recorder::Done, &recorder, Recorder::Release, &id));
        ntk_debug_probe_cancel(id);
        ASSERT_TRUE(recorder.WaitFor("release", 1)) << "round " << round;
        ntk_debug_probe_finish(id, 5);
        ntktest::DrainMain();
        std::vector<Record> records = recorder.Records();
        ASSERT_EQ((std::vector<std::string>{"done", "release"}), Names(records)) << "round " << round;
        EXPECT_EQ(kCanceled, records[0].error);
    }
}

TEST_F(Probe, ACancelBeforeTheInsertionRunsCompletesCanceledAndNeverEntersTheLedger) {
    Recorder& recorder = Leaked<Recorder>();
    uint64_t id = 0;
    ntktest::HoldMain();
    ASSERT_EQ(kNone, ntk_debug_probe_start(Recorder::Done, &recorder, Recorder::Release, &id));
    ntk_debug_probe_cancel(id);
    EXPECT_EQ(0u, recorder.Records().size());
    ntktest::UnholdMain();
    ASSERT_TRUE(recorder.WaitFor("release", 1));
    std::vector<Record> records = recorder.Records();
    ASSERT_EQ((std::vector<std::string>{"done", "release"}), Names(records));
    EXPECT_EQ(kCanceled, records[0].error);
}

TEST_F(Probe, AResultAndACancelQueuedTogetherCompleteCanceledOnceInEitherOrder) {
    for (bool cancel_first : {false, true}) {
        Recorder& recorder = Leaked<Recorder>();
        uint64_t id = 0;
        ASSERT_EQ(kNone, ntk_debug_probe_start(Recorder::Done, &recorder, Recorder::Release, &id));
        ntktest::DrainMain();
        ntktest::HoldMain();
        if (cancel_first) ntk_debug_probe_cancel(id);
        ntk_debug_probe_finish(id, 7);
        if (!cancel_first) ntk_debug_probe_cancel(id);
        ntktest::UnholdMain();
        ASSERT_TRUE(recorder.WaitFor("release", 1));
        ntktest::DrainMain();
        std::vector<Record> records = recorder.Records();
        // The cancel moved the state before the main thread saw the result, so the result is dropped.
        ASSERT_EQ((std::vector<std::string>{"done", "release"}), Names(records)) << "cancel first " << cancel_first;
        EXPECT_EQ(kCanceled, records[0].error);
    }
}

TEST_F(Probe, ACancelAfterTheResultArrivedChangesNothing) {
    Recorder& recorder = Leaked<Recorder>();
    uint64_t id = 0;
    ASSERT_EQ(kNone, ntk_debug_probe_start(Recorder::Done, &recorder, Recorder::Release, &id));
    ntk_debug_probe_finish(id, 9);
    ASSERT_TRUE(recorder.WaitFor("release", 1));
    ntk_debug_probe_cancel(id);
    ntk_debug_probe_cancel(0x7FFFFFFFFFFFull);
    ntktest::DrainMain();
    std::vector<Record> records = recorder.Records();
    ASSERT_EQ((std::vector<std::string>{"done", "release"}), Names(records));
    EXPECT_EQ(9, records[0].value);
}

TEST_F(Probe, EveryListenerOfTheKindGetsTheEventOnMain) {
    Recorder& first = Leaked<Recorder>();
    Recorder& second = Leaked<Recorder>();
    uint64_t a = 0;
    uint64_t b = 0;
    ASSERT_EQ(kNone, ntk_debug_probe_add_listener(Recorder::Event, &first, Recorder::Release, &a));
    ASSERT_EQ(kNone, ntk_debug_probe_add_listener(Recorder::Event, &second, Recorder::Release, &b));
    ASSERT_EQ(kNone, ntk_debug_probe_emit(11));
    ASSERT_TRUE(first.WaitFor("event", 1));
    ASSERT_TRUE(second.WaitFor("event", 1));
    EXPECT_TRUE(first.Records()[0].on_main);
    EXPECT_EQ(11, second.Records()[0].value);
    ntk_debug_probe_listener_remove(a);
    ntk_debug_probe_emit(12);
    ASSERT_TRUE(second.WaitFor("event", 2));
    ntk_debug_probe_listener_remove(b);
    ASSERT_TRUE(first.WaitFor("release", 1));
    ASSERT_TRUE(second.WaitFor("release", 1));
    ntktest::DrainMain();
    EXPECT_EQ((std::vector<std::string>{"event", "release"}), Names(first.Records()));
    EXPECT_EQ((std::vector<std::string>{"event", "event", "release"}), Names(second.Records()));
    EXPECT_TRUE(first.Records()[1].on_main);
}

TEST_F(Probe, AddingAndRemovingInOneMainMessageDeliversNothing) {
    Recorder& recorder = Leaked<Recorder>();
    ntktest::RunOnMain([&] {
        uint64_t handle = 0;
        ASSERT_EQ(kNone, ntk_debug_probe_add_listener(Recorder::Event, &recorder, Recorder::Release, &handle));
        ntk_debug_probe_emit(1);
        ntk_debug_probe_listener_remove(handle);
    });
    ASSERT_TRUE(recorder.WaitFor("release", 1));
    ntktest::DrainMain();
    EXPECT_EQ((std::vector<std::string>{"release"}), Names(recorder.Records()));
    EXPECT_TRUE(recorder.Records()[0].on_main);
}

namespace {
struct SelfRemoving {
    Recorder& recorder = Leaked<Recorder>();
    uint64_t handle = 0;
};
void RemoveItself(void* user_data, int64_t value) {
    auto* self = static_cast<SelfRemoving*>(user_data);
    self->recorder.Add({"event", 0, value});
    ntk_debug_probe_listener_remove(self->handle);
}
void ReleaseSelf(void* user_data) {
    static_cast<SelfRemoving*>(user_data)->recorder.Add({"release"});
}
}  // namespace

TEST_F(Probe, ARemovalInsideTheCallbackStopsTheDeliveriesAtOnce) {
    SelfRemoving& self = Leaked<SelfRemoving>();
    ntktest::HoldMain();
    ASSERT_EQ(kNone, ntk_debug_probe_add_listener(RemoveItself, &self, ReleaseSelf, &self.handle));
    ntk_debug_probe_emit(1);
    ntk_debug_probe_emit(2);
    ntk_debug_probe_emit(3);
    ntktest::UnholdMain();
    ASSERT_TRUE(self.recorder.WaitFor("release", 1));
    ntktest::DrainMain();
    EXPECT_EQ((std::vector<std::string>{"event", "release"}), Names(self.recorder.Records()));
}

TEST_F(Probe, ARemovalRacingDeliveriesReleasesOnceAndDeliversNothingAfter) {
    for (int round = 0; round < 20; ++round) {
        Recorder& recorder = Leaked<Recorder>();
        uint64_t handle = 0;
        ASSERT_EQ(kNone, ntk_debug_probe_add_listener(Recorder::Event, &recorder, Recorder::Release, &handle));
        std::atomic<bool> go{false};
        std::thread emitter([&] {
            while (!go.load()) {
            }
            for (int i = 0; i < 200; ++i) ntk_debug_probe_emit(i);
        });
        go.store(true);
        std::this_thread::sleep_for(std::chrono::microseconds(200 * (round % 5)));
        ntk_debug_probe_listener_remove(handle);
        emitter.join();
        ASSERT_TRUE(recorder.WaitFor("release", 1));
        ntktest::DrainMain();
        std::vector<Record> records = recorder.Records();
        ASSERT_EQ(1u, recorder.Count("release")) << "round " << round;
        EXPECT_EQ("release", records.back().what) << "round " << round;
    }
}
