// Dialogs through the C ABI (C ABI design part 2, 6.2, 11.1, 12.1 and 12.2; part 1, 1.3 and
// 5.7). The runner gives the test app a plain Activity, so the dialogs show on the transparent
// host; UiDriver presses them.
#include <gtest/gtest.h>

#include <unistd.h>

#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include <NativeToolkitC/Dialog.h>

#include "../TestSupport.h"

using ntktest::Leaked;
using ntktest::Recorder;

namespace {

// What a dialog's callback received, with the result copied out and freed.
struct Answer {
    uint64_t request_id = 0;
    ntk_dialog_error error = -1;
    uint32_t system_code = 99;
    bool had_result = false;
    ntk_dialog_answer answer = -1;
    ntk_dialog_button button = -1;
    std::string button_text = "<null>";
    int32_t checked_index = -2;
    std::vector<int32_t> checked;
    std::string text = "<null>";
    std::string username = "<null>";
    std::string password = "<null>";
};

struct Waiter {
    Recorder recorder;
    std::mutex mutex;
    Answer answer;
};

std::string Read(const char* text, size_t size) { return text == nullptr ? "<null>" : std::string(text, size); }

void OnResult(void* user_data, uint64_t request_id, ntk_dialog_error error, uint32_t system_code,
              ntk_dialog_result* result) {
    auto* waiter = static_cast<Waiter*>(user_data);
    {
        std::lock_guard<std::mutex> lock(waiter->mutex);
        Answer& a = waiter->answer;
        a.request_id = request_id;
        a.error = error;
        a.system_code = system_code;
        a.had_result = result != nullptr;
        if (result != nullptr) {
            size_t size = 0;
            a.answer = ntk_dialog_result_answer(result);
            a.button = ntk_dialog_result_button(result);
            a.button_text = Read(ntk_dialog_result_button_text(result, &size), size);
            a.checked_index = ntk_dialog_result_checked_index(result);
            for (size_t i = 0; i < ntk_dialog_result_checked_count(result); ++i) {
                a.checked.push_back(ntk_dialog_result_checked_at(result, i));
            }
            a.text = Read(ntk_dialog_result_text(result, &size), size);
            a.username = Read(ntk_dialog_result_username(result, &size), size);
            a.password = Read(ntk_dialog_result_password(result, &size), size);
            ntk_dialog_result_free(result);
        }
    }
    waiter->recorder.Add({"done", error});
}

Answer Await(Waiter& waiter) {
    EXPECT_TRUE(waiter.recorder.WaitFor("release", 1, std::chrono::seconds(10)));
    ntktest::DrainMain();
    // The completion came once, on main, and the release after it (part 1, 5.7).
    std::vector<ntktest::Record> records = waiter.recorder.Records();
    EXPECT_EQ(2u, records.size());
    if (records.size() == 2) {
        EXPECT_EQ("done", records[0].what);
        EXPECT_EQ("release", records[1].what);
        EXPECT_TRUE(records[0].on_main);
        EXPECT_TRUE(records[1].on_main);
    }
    std::lock_guard<std::mutex> lock(waiter.mutex);
    return waiter.answer;
}

template <class T>
T Request() {
    T request{};
    request.struct_size = sizeof(T);
    return request;
}

class Dialog : public testing::Test {
protected:
    void TearDown() override { ntktest::DrainMain(); }
};

}  // namespace

// --- the entry (12.1, 入口の検査; AP-19) ---

TEST_F(Dialog, InvalidRequestsAreRejectedAtTheEntryAndReleasedHere) {
    Waiter& waiter = Leaked<Waiter>();
    uint64_t id = 99;
    auto alert = Request<ntk_dialog_alert_request>();
    EXPECT_EQ(NTK_DIALOG_ERROR_INVALID_PARAMETER,
              ntk_dialog_show_alert_async(&alert, nullptr, &waiter, Recorder::Release, &id));
    EXPECT_EQ(0u, id);
    EXPECT_EQ(NTK_DIALOG_ERROR_INVALID_PARAMETER,
              ntk_dialog_show_alert_async(nullptr, OnResult, &waiter, Recorder::Release, &id));
    auto small = alert;
    small.struct_size = 8;
    EXPECT_EQ(NTK_DIALOG_ERROR_INVALID_PARAMETER,
              ntk_dialog_show_alert_async(&small, OnResult, &waiter, Recorder::Release, &id));
    auto reserved = alert;
    reserved.reserved0 = 1;
    EXPECT_EQ(NTK_DIALOG_ERROR_INVALID_PARAMETER,
              ntk_dialog_show_alert_async(&reserved, OnResult, &waiter, Recorder::Release, &id));
    auto bad_text = alert;
    bad_text.title = "\xED\xA0\x80";
    EXPECT_EQ(NTK_DIALOG_ERROR_INVALID_PARAMETER,
              ntk_dialog_show_alert_async(&bad_text, OnResult, &waiter, Recorder::Release, &id));

    const char* items[] = {"a", "b", "c"};
    auto single = Request<ntk_dialog_single_choice_request>();
    single.items = items;
    single.item_count = 0;
    EXPECT_EQ(NTK_DIALOG_ERROR_INVALID_PARAMETER,
              ntk_dialog_show_single_choice_async(&single, OnResult, &waiter, Recorder::Release, &id));
    single.item_count = 3;
    single.checked_index = 3;
    EXPECT_EQ(NTK_DIALOG_ERROR_INVALID_PARAMETER,
              ntk_dialog_show_single_choice_async(&single, OnResult, &waiter, Recorder::Release, &id));
    single.checked_index = -2;
    EXPECT_EQ(NTK_DIALOG_ERROR_INVALID_PARAMETER,
              ntk_dialog_show_single_choice_async(&single, OnResult, &waiter, Recorder::Release, &id));
    single.checked_index = 0;
    single.reserved1 = 1;
    EXPECT_EQ(NTK_DIALOG_ERROR_INVALID_PARAMETER,
              ntk_dialog_show_single_choice_async(&single, OnResult, &waiter, Recorder::Release, &id));
    const char* with_null[] = {"a", nullptr};
    auto multi = Request<ntk_dialog_multi_choice_request>();
    multi.items = with_null;
    multi.item_count = 2;
    EXPECT_EQ(NTK_DIALOG_ERROR_INVALID_PARAMETER,
              ntk_dialog_show_multi_choice_async(&multi, OnResult, &waiter, Recorder::Release, &id));

    // A newer header's request with a value in its new part.
    std::vector<unsigned char> newer(sizeof(ntk_dialog_alert_request) + 8, 0);
    alert.struct_size = static_cast<uint32_t>(newer.size());
    std::memcpy(newer.data(), &alert, sizeof(alert));
    newer.back() = 1;
    EXPECT_EQ(NTK_DIALOG_ERROR_NOT_SUPPORTED,
              ntk_dialog_show_alert_async(reinterpret_cast<const ntk_dialog_alert_request*>(newer.data()), OnResult,
                                          &waiter, Recorder::Release, &id));

    // Every rejection released on this thread before returning, and nothing completed.
    ASSERT_EQ(11u, waiter.recorder.Count("release"));
    for (const auto& record : waiter.recorder.Records()) EXPECT_EQ(gettid(), record.thread);
    ntktest::DrainMain();
    EXPECT_EQ(0u, waiter.recorder.Count("done"));
}

// --- the six answers (12.1 Dialog, 12.2) ---

TEST_F(Dialog, AnAlertAnswersWithItsButton) {
    Waiter& waiter = Leaked<Waiter>();
    auto request = Request<ntk_dialog_alert_request>();
    request.title = "Alert title";
    request.message = "Alert message";
    uint64_t id = 0;
    ASSERT_EQ(NTK_DIALOG_ERROR_NONE, ntk_dialog_show_alert_async(&request, OnResult, &waiter, Recorder::Release, &id));
    EXPECT_NE(0u, id);
    ASSERT_TRUE(ntktest::UiWaitText("Alert message"));
    ASSERT_TRUE(ntktest::UiClick("OK"));
    Answer a = Await(waiter);
    EXPECT_EQ(id, a.request_id);
    EXPECT_EQ(NTK_DIALOG_ERROR_NONE, a.error);
    EXPECT_EQ(0u, a.system_code);
    EXPECT_EQ(NTK_DIALOG_ANSWER_BUTTON, a.answer);
    EXPECT_EQ(NTK_DIALOG_BUTTON_POSITIVE, a.button);
    EXPECT_EQ("OK", a.button_text);
}

TEST_F(Dialog, AConfirmAnswersWithTheButtonPressed) {
    Waiter& waiter = Leaked<Waiter>();
    auto request = Request<ntk_dialog_confirm_request>();
    request.message = "Confirm message";
    request.negative_text = "Nope";
    ASSERT_EQ(NTK_DIALOG_ERROR_NONE, ntk_dialog_show_confirm_async(&request, OnResult, &waiter, Recorder::Release, nullptr));
    ASSERT_TRUE(ntktest::UiWaitText("Confirm message"));
    ASSERT_TRUE(ntktest::UiWaitText("Yes"));  // the default positive text
    ASSERT_TRUE(ntktest::UiClick("Nope"));
    Answer a = Await(waiter);
    EXPECT_EQ(NTK_DIALOG_ERROR_NONE, a.error);
    EXPECT_EQ(NTK_DIALOG_BUTTON_NEGATIVE, a.button);
    EXPECT_EQ("Nope", a.button_text);
}

TEST_F(Dialog, ASingleChoiceAnswersWithTheCheckedIndex) {
    Waiter& waiter = Leaked<Waiter>();
    const char* items[] = {"apple", "banana", "cherry"};
    auto request = Request<ntk_dialog_single_choice_request>();
    request.title = "Pick one";
    request.items = items;
    request.item_count = 3;
    request.checked_index = -1;
    ASSERT_EQ(NTK_DIALOG_ERROR_NONE,
              ntk_dialog_show_single_choice_async(&request, OnResult, &waiter, Recorder::Release, nullptr));
    ASSERT_TRUE(ntktest::UiClick("banana"));
    ASSERT_TRUE(ntktest::UiClick("OK"));
    Answer a = Await(waiter);
    EXPECT_EQ(NTK_DIALOG_ERROR_NONE, a.error);
    EXPECT_EQ(1, a.checked_index);
}

TEST_F(Dialog, AZeroFilledSingleChoiceChecksTheFirstItem) {
    // A zero-filled request is Kotlin's default dialog (part 2, 6.2): checked_index 0.
    Waiter& waiter = Leaked<Waiter>();
    const char* items[] = {"first", "second"};
    auto request = Request<ntk_dialog_single_choice_request>();
    request.items = items;
    request.item_count = 2;
    ASSERT_EQ(NTK_DIALOG_ERROR_NONE,
              ntk_dialog_show_single_choice_async(&request, OnResult, &waiter, Recorder::Release, nullptr));
    ASSERT_TRUE(ntktest::UiWaitText("second"));
    ASSERT_TRUE(ntktest::UiClick("OK"));
    Answer a = Await(waiter);
    EXPECT_EQ(0, a.checked_index);
}

TEST_F(Dialog, AMultiChoiceAnswersWithEveryItem) {
    Waiter& waiter = Leaked<Waiter>();
    const char* items[] = {"red", "green", "blue"};
    const int32_t checked[] = {0, 1, 0};
    auto request = Request<ntk_dialog_multi_choice_request>();
    request.items = items;
    request.item_count = 3;
    request.checked = checked;
    ASSERT_EQ(NTK_DIALOG_ERROR_NONE,
              ntk_dialog_show_multi_choice_async(&request, OnResult, &waiter, Recorder::Release, nullptr));
    ASSERT_TRUE(ntktest::UiClick("red"));
    ASSERT_TRUE(ntktest::UiClick("OK"));
    Answer a = Await(waiter);
    EXPECT_EQ(NTK_DIALOG_ERROR_NONE, a.error);
    EXPECT_EQ((std::vector<int32_t>{1, 1, 0}), a.checked);
}

TEST_F(Dialog, ATextInputAnswersWithTheText) {
    Waiter& waiter = Leaked<Waiter>();
    auto request = Request<ntk_dialog_text_input_request>();
    request.message = "Type something";
    ASSERT_EQ(NTK_DIALOG_ERROR_NONE,
              ntk_dialog_show_text_input_async(&request, OnResult, &waiter, Recorder::Release, nullptr));
    ASSERT_TRUE(ntktest::UiWaitText("Type something"));
    ASSERT_TRUE(ntktest::UiType(0, "h\xC3\xA9llo"));
    ASSERT_TRUE(ntktest::UiClick("OK"));
    Answer a = Await(waiter);
    EXPECT_EQ(NTK_DIALOG_ERROR_NONE, a.error);
    EXPECT_EQ("h\xC3\xA9llo", a.text);
}

TEST_F(Dialog, ALoginAnswersWithTheUsernameAndPassword) {
    Waiter& waiter = Leaked<Waiter>();
    auto request = Request<ntk_dialog_login_request>();
    request.message = "Sign in";
    ASSERT_EQ(NTK_DIALOG_ERROR_NONE, ntk_dialog_show_login_async(&request, OnResult, &waiter, Recorder::Release, nullptr));
    ASSERT_TRUE(ntktest::UiWaitText("Sign in"));
    ASSERT_TRUE(ntktest::UiType(0, "user"));
    ASSERT_TRUE(ntktest::UiType(1, "secret"));
    ASSERT_TRUE(ntktest::UiClick("Login"));
    Answer a = Await(waiter);
    EXPECT_EQ(NTK_DIALOG_ERROR_NONE, a.error);
    EXPECT_EQ("user", a.username);
    EXPECT_EQ("secret", a.password);
}

TEST_F(Dialog, BackDismissesWithNoValues) {
    // AP-13: DISMISSED carries nothing; the readers give their defaults.
    Waiter& waiter = Leaked<Waiter>();
    const char* items[] = {"x", "y"};
    auto request = Request<ntk_dialog_single_choice_request>();
    request.title = "Dismiss me";
    request.items = items;
    request.item_count = 2;
    request.checked_index = 1;
    ASSERT_EQ(NTK_DIALOG_ERROR_NONE,
              ntk_dialog_show_single_choice_async(&request, OnResult, &waiter, Recorder::Release, nullptr));
    ASSERT_TRUE(ntktest::UiWaitText("Dismiss me"));
    ntktest::UiBack();
    Answer a = Await(waiter);
    EXPECT_EQ(NTK_DIALOG_ERROR_NONE, a.error);
    EXPECT_TRUE(a.had_result);
    EXPECT_EQ(NTK_DIALOG_ANSWER_DISMISSED, a.answer);
    EXPECT_EQ(-1, a.checked_index);
    EXPECT_TRUE(a.checked.empty());
    EXPECT_EQ("<null>", a.button_text);
    EXPECT_EQ("<null>", a.text);
}

// --- cancel, the host, the foreground ---

TEST_F(Dialog, CancelCompletesCanceledAndClosesTheDialog) {
    Waiter& waiter = Leaked<Waiter>();
    auto request = Request<ntk_dialog_alert_request>();
    request.message = "To be canceled";
    uint64_t id = 0;
    ASSERT_EQ(NTK_DIALOG_ERROR_NONE, ntk_dialog_show_alert_async(&request, OnResult, &waiter, Recorder::Release, &id));
    ASSERT_TRUE(ntktest::UiWaitText("To be canceled"));
    EXPECT_EQ(NTK_DIALOG_ERROR_NONE, ntk_dialog_cancel(id));
    Answer a = Await(waiter);
    EXPECT_EQ(NTK_DIALOG_ERROR_CANCELED, a.error);
    EXPECT_FALSE(a.had_result);
    EXPECT_EQ(id, a.request_id);
    EXPECT_TRUE(ntktest::UiGone("To be canceled"));
    // After the completion, and for an unknown id, cancel does nothing.
    EXPECT_EQ(NTK_DIALOG_ERROR_NONE, ntk_dialog_cancel(id));
    EXPECT_EQ(NTK_DIALOG_ERROR_NONE, ntk_dialog_cancel(0x7FFFFFFFFFFFull));
}

TEST_F(Dialog, ARequestCanceledBeforeItsInsertionIsNeverShown) {
    // Part 1, 5.7: the insertion of a request already CANCEL_REQUESTED starts nothing.
    Waiter& waiter = Leaked<Waiter>();
    auto request = Request<ntk_dialog_alert_request>();
    request.message = "Never shown";
    uint64_t id = 0;
    int32_t before = ntktest::ActivitiesCreated();
    ntktest::HoldMain();
    ASSERT_EQ(NTK_DIALOG_ERROR_NONE, ntk_dialog_show_alert_async(&request, OnResult, &waiter, Recorder::Release, &id));
    ntk_dialog_cancel(id);
    ntktest::UnholdMain();
    Answer a = Await(waiter);
    EXPECT_EQ(NTK_DIALOG_ERROR_CANCELED, a.error);
    // Not even briefly: the transparent host was never created (the test Activity is not a
    // FragmentActivity, so any dialog would need one).
    EXPECT_TRUE(ntktest::UiStaysAway("Never shown", 1500));
    EXPECT_EQ(before, ntktest::ActivitiesCreated());
}

TEST_F(Dialog, ADestroyedHostCompletesCanceledBySystem) {
    Waiter& waiter = Leaked<Waiter>();
    auto request = Request<ntk_dialog_alert_request>();
    request.message = "Host goes away";
    ASSERT_EQ(NTK_DIALOG_ERROR_NONE, ntk_dialog_show_alert_async(&request, OnResult, &waiter, Recorder::Release, nullptr));
    ASSERT_TRUE(ntktest::UiWaitText("Host goes away"));
    ASSERT_TRUE(ntktest::UiFinishForeground());
    Answer a = Await(waiter);
    EXPECT_EQ(NTK_DIALOG_ERROR_CANCELED_BY_SYSTEM, a.error);
    EXPECT_FALSE(a.had_result);
}

TEST_F(Dialog, FromTheBackTheDialogCompletesNotForeground) {
    ASSERT_TRUE(ntktest::UiHome());
    Waiter& waiter = Leaked<Waiter>();
    auto request = Request<ntk_dialog_alert_request>();
    request.message = "Not in front";
    ASSERT_EQ(NTK_DIALOG_ERROR_NONE, ntk_dialog_show_alert_async(&request, OnResult, &waiter, Recorder::Release, nullptr));
    Answer a = Await(waiter);
    EXPECT_EQ(NTK_DIALOG_ERROR_NOT_FOREGROUND, a.error);
    EXPECT_FALSE(a.had_result);
}
