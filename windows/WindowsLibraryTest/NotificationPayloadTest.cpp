#include "pch.h"
#include "Notification/Data/WindowsClassicActivator.h"
#include "Notification/WindowsNotificationManagerInternal.h"
#include "AppSdkRuntimeForTest.h"

#include <functional>
#include <string>

using namespace Microsoft::VisualStudio::CppUnitTestFramework;
using namespace winrt::Windows::Data::Json;

// ============================================================================
// T-17: what the notification payload accepts, read out of the implementation
// rather than out of a reading of it.
//
// The input inventory records what each JSON key does when it is present and
// when it is left out. It does not record the third case - present and empty -
// and T-14 found that the two are not the same thing twelve times over: the
// implementation branches on HasKey, so "" is a value, while an empty string
// in NotificationContent means the field is not there at all.
//
// Each test below pins what the payload does today with one of those twelve.
// They are written against the JSON entry point, which T-14 is about to move
// onto the struct, and they have to keep passing afterwards: that is the whole
// of "the C ABI behaves the same", made checkable.
// ============================================================================

namespace WindowsNotificationPayloadTest
{

namespace
{
    /// A backend that accepts everything, so Show gets as far as building.
    struct AcceptingBackend final : public INotificationBackend
    {
        void RegisterActivation(DWORD* pError) override { if (pError) *pError = NOTIFICATION_SUCCESS; }
        void UnregisterActivation() override {}
        void Deliver(const DeliverPayload&, DWORD* pError) override { if (pError) *pError = NOTIFICATION_SUCCESS; }
        void Schedule(const DeliverPayload&, int64_t, DWORD* pError) override { if (pError) *pError = NOTIFICATION_SUCCESS; }
        void CancelSchedule(const wchar_t*, const wchar_t*, DWORD* pError) override { if (pError) *pError = NOTIFICATION_SUCCESS; }
        void SetBadge(int, DWORD* pError) override { if (pError) *pError = NOTIFICATION_SUCCESS; }
        void UpdateProgress(const wchar_t*, const wchar_t*, double, const wchar_t*,
                            const wchar_t*, uint32_t, DWORD* pError) override { if (pError) *pError = NOTIFICATION_SUCCESS; }
        void RemoveByTag(const wchar_t*, const wchar_t*, DWORD* pError) override { if (pError) *pError = NOTIFICATION_SUCCESS; }
        void RemoveAll(DWORD* pError) override { if (pError) *pError = NOTIFICATION_SUCCESS; }
        void RemoveById(uint32_t, DWORD* pError) override { if (pError) *pError = NOTIFICATION_SUCCESS; }
        void GetAll(wchar_t*, uint32_t, DWORD* pError) override { if (pError) *pError = NOTIFICATION_SUCCESS; }
        int  Setting() override { return 0; }
    };
}

TEST_CLASS(NotificationPayloadTest)
{
public:

    TEST_CLASS_INITIALIZE(StartRuntime)
    {
        try { winrt::init_apartment(); } catch (winrt::hresult_error const&) {}
        const std::wstring& failure = AppSdkRuntimeForTest::Ensure();
        if (!failure.empty()) Assert::Fail(failure.c_str());
    }

    TEST_METHOD_INITIALIZE(InstallABackend)
    {
        auto& backing = WindowsNotificationManager::GetInstance();
        backing.SetBackendForTest(std::make_unique<AcceptingBackend>());
        backing.m_initialized = true;
    }

    TEST_METHOD_CLEANUP(RemoveTheBackend)
    {
        auto& backing = WindowsNotificationManager::GetInstance();
        backing.m_initialized = false;
        backing.SetBackendForTest(nullptr);
    }

    // --- Text that is there but empty ---------------------------------------

    TEST_METHOD(Test_AnEmptyTitle_StillEmitsATextElement)
    {
        // An absent title emits nothing; an empty one emits an empty line.
        Assert::AreEqual<size_t>(0, TextElements(LR"({})"), L"no title");
        Assert::AreEqual<size_t>(1, TextElements(LR"({"title":""})"), L"an empty title");
        Assert::AreEqual<size_t>(1, TextElements(LR"({"title":"t"})"), L"a title");
    }

    TEST_METHOD(Test_AnEmptyBody_StillEmitsASecondTextElement)
    {
        Assert::AreEqual<size_t>(1, TextElements(LR"({"title":"t"})"), L"no body");
        Assert::AreEqual<size_t>(2, TextElements(LR"({"title":"t","body":""})"), L"an empty body");
    }

    TEST_METHOD(Test_AnEmptyAttribution_StillEmitsIt)
    {
        Assert::IsFalse(Contains(LR"({"title":"t"})", L"placement='attribution'"), L"no attribution");
        Assert::IsTrue(Contains(LR"({"title":"t","attribution":""})", L"placement='attribution'"),
                       L"an empty attribution");
    }

    TEST_METHOD(Test_AnEmptyProgressTitle_StillSetsIt)
    {
        Assert::IsFalse(Contains(LR"({"title":"t","progress":{"value":0.5}})", L"title="),
                        L"no progress title");
        Assert::IsTrue(Contains(LR"({"title":"t","progress":{"title":"","value":0.5}})", L"title=''"),
                       L"an empty progress title");
    }

    // --- An empty URI is a bad URI, not an absent one ------------------------

    TEST_METHOD(Test_AnEmptyHeroImage_IsAnHResultFailure)
    {
        Assert::AreEqual<DWORD>(NOTIFICATION_SUCCESS, ShowError(LR"({"title":"t"})"), L"no hero image");
        Assert::AreEqual<DWORD>(NOTIFICATION_ERROR_HRESULT_FAILURE,
                                ShowError(LR"({"title":"t","heroImage":""})"), L"an empty hero image");
    }

    TEST_METHOD(Test_AnEmptyInlineImage_IsAnHResultFailure)
    {
        Assert::AreEqual<DWORD>(NOTIFICATION_ERROR_HRESULT_FAILURE,
                                ShowError(LR"({"title":"t","inlineImage":""})"));
    }

    TEST_METHOD(Test_AnEmptyAudioUri_IsAnHResultFailureWhileAMissingOneIsInvalidParameter)
    {
        // The two are different: no uri key at all is caught by the check in
        // ApplyAudio, an empty one gets as far as constructing the Uri.
        Assert::AreEqual<DWORD>(NOTIFICATION_ERROR_INVALID_PARAMETER,
                                ShowError(LR"({"title":"t","audio":{"type":"uri"}})"), L"no uri");
        Assert::AreEqual<DWORD>(NOTIFICATION_ERROR_HRESULT_FAILURE,
                                ShowError(LR"({"title":"t","audio":{"type":"uri","uri":""}})"),
                                L"an empty uri");
    }

    TEST_METHOD(Test_AnEmptyButtonInvokeUri_IsAnHResultFailure)
    {
        Assert::AreEqual<DWORD>(NOTIFICATION_ERROR_HRESULT_FAILURE,
                                ShowError(LR"({"title":"t","buttons":[{"label":"b","invokeUri":""}]})"));
    }

    // --- Presence decides which overload is called --------------------------

    TEST_METHOD(Test_AnEmptyPlaceholder_StillPicksTheThreeArgumentTextBox)
    {
        // With neither key the one-argument overload is used, and the XML
        // differs: no placeHolderContent attribute.
        Assert::IsFalse(Contains(LR"({"title":"t","textBoxes":[{"id":"x"}]})", L"placeHolderContent"),
                        L"neither key");
        Assert::IsTrue(Contains(LR"({"title":"t","textBoxes":[{"id":"x","placeholder":""}]})",
                                L"placeHolderContent"), L"an empty placeholder");
    }

    TEST_METHOD(Test_AnEmptyComboTitleOrSelection_IsTheSameAsNone)
    {
        // Unlike the text elements above, these two come out the same: the
        // builder is asked to set them, and drops an empty value of its own
        // accord. Worth pinning, because reading the payload code alone says
        // the opposite - HasKey is true, so Title() and SelectedItem() are
        // called - and only the App SDK knows what it does with "".
        Assert::AreEqual(Describe(LR"({"title":"t","comboBoxes":[{"id":"c"}]})"),
                         Describe(LR"({"title":"t","comboBoxes":[{"id":"c","title":""}]})"),
                         L"an empty combo title");
        Assert::AreEqual(Describe(LR"({"title":"t","comboBoxes":[{"id":"c"}]})"),
                         Describe(LR"({"title":"t","comboBoxes":[{"id":"c","defaultSelection":""}]})"),
                         L"an empty default selection");
    }

    TEST_METHOD(Test_AnEmptyArgsObjectStillCollidesWithInvokeUri)
    {
        // The exclusivity is about the keys, not about what they hold: an empty
        // args object and an invokeUri together are still a violation.
        Assert::AreEqual<DWORD>(NOTIFICATION_ERROR_INVALID_PARAMETER,
                                ShowError(LR"({"title":"t","buttons":)"
                                          LR"([{"label":"b","args":{},"invokeUri":"https://e.com"}]})"));
        Assert::AreEqual<DWORD>(NOTIFICATION_SUCCESS,
                                ShowError(LR"({"title":"t","buttons":)"
                                          LR"([{"label":"b","invokeUri":"https://e.com"}]})"),
                                L"the invoke URI on its own");
    }

    // --- Cases where an empty value is the same as an absent one -------------

    TEST_METHOD(Test_AnEmptyTagOrGroup_IsTheSameAsNone)
    {
        // Worth pinning: these two look like the others but are not, because
        // an empty tag and no tag are the same thing to the notification.
        Assert::AreEqual(Describe(LR"({"title":"t"})"),
                         Describe(LR"({"title":"t","tag":"","group":""})"));
    }

    TEST_METHOD(Test_AnUnknownScenarioOrEvent_IsSilentlyTheDefault)
    {
        Assert::AreEqual(Describe(LR"({"title":"t"})"),
                         Describe(LR"({"title":"t","scenario":""})"), L"an empty scenario");
        Assert::AreEqual(Describe(LR"({"title":"t","audio":{"event":"nonesuch"}})"),
                         Describe(LR"({"title":"t","audio":{"event":""}})"), L"an empty event");
    }

private:

    /// The XML the payload builds, with its tag and group.
    static std::wstring Describe(const wchar_t* payload)
    {
        DWORD error = NOTIFICATION_SUCCESS;
        auto builder = WindowsNotificationManager::GetInstance().BuildFromJson(
            JsonObject::Parse(payload), &error);
        Assert::AreEqual<DWORD>(NOTIFICATION_SUCCESS, error, L"the payload was rejected");
        auto notification = builder.BuildNotification();
        return L"tag=" + std::wstring{notification.Tag()}
             + L" group=" + std::wstring{notification.Group()}
             + L" " + std::wstring{notification.Payload()};
    }

    static bool Contains(const wchar_t* payload, const wchar_t* fragment)
    {
        return Describe(payload).find(fragment) != std::wstring::npos;
    }

    static size_t TextElements(const wchar_t* payload)
    {
        const std::wstring xml = Describe(payload);
        size_t count = 0;
        for (size_t at = xml.find(L"<text"); at != std::wstring::npos; at = xml.find(L"<text", at + 1)) {
            // The attribution line is a text element with a placement; it is
            // counted by its own test.
            if (xml.compare(at, 18, L"<text placement='a") != 0) ++count;
        }
        return count;
    }

    /// What a C caller would read from pError for this payload.
    static DWORD ShowError(const wchar_t* payload)
    {
        DWORD error = 0xFFFFFFFFu;
        WindowsNotificationManager::GetInstance().Show(payload, &error);
        return error;
    }
};

}  // namespace WindowsNotificationPayloadTest
