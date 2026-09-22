#include "pch.h"
#include "Notification/Data/WindowsClassicActivator.h"
#include "Notification/WindowsNotificationManagerInternal.h"
#include "Notification/WindowsNotificationApiInternal.h"
#include "Support/NotificationPayloadJson.h"
#include "Support/AppSdkRuntimeForTest.h"

#include <functional>
#include <optional>
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
// Each test below pins what the C++ API does with one of those cases: a
// NotificationContent is written down as JSON (the test helper
// Support/NotificationPayloadJson reads it, keeping present-but-empty apart
// from absent), Manager::Show validates and builds it, and a recording backend
// hands back the XML that would have been delivered. The 1.x C ABI that took
// this JSON is gone (stage 5); what it established about the content is not,
// and this is where the C++ side of it stays pinned.
// ============================================================================

namespace WindowsNotificationPayloadTest
{

namespace
{
    /// A backend that accepts everything and keeps what it was given, so a
    /// test can read the XML the payload turned into.
    struct AcceptingBackend final : public INotificationBackend
    {
        DeliverPayload last;

        void RegisterActivation(DWORD* pError) override { if (pError) *pError = NOTIFICATION_SUCCESS; }
        void UnregisterActivation() override {}
        void Deliver(const DeliverPayload& payload, DWORD* pError) override
        {
            last = payload;
            if (pError) *pError = NOTIFICATION_SUCCESS;
        }
        void Schedule(const DeliverPayload& payload, int64_t, DWORD* pError) override
        {
            last = payload;
            if (pError) *pError = NOTIFICATION_SUCCESS;
        }
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

    AcceptingBackend* g_backend = nullptr;

    /// One manager for the whole of a test. Closing one uninitialises the
    /// manager underneath it, so a fresh one per call would leave the second
    /// call with nothing to talk to.
    std::optional<NativeToolkit::Notification::Manager> g_manager;
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
        auto backend = std::make_unique<AcceptingBackend>();
        g_backend = backend.get();
        auto& backing = WindowsNotificationManager::GetInstance();
        backing.SetBackendForTest(std::move(backend));
        backing.m_initialized = true;
        g_manager.emplace(NativeToolkit::Notification::Detail::TestAccess::MakeManager());
    }

    TEST_METHOD_CLEANUP(RemoveTheBackend)
    {
        g_manager.reset();
        auto& backing = WindowsNotificationManager::GetInstance();
        backing.m_initialized = false;
        backing.SetBackendForTest(nullptr);
        g_backend = nullptr;

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

    /// The XML the content the payload describes builds, with its tag and group.
    static std::wstring Describe(const wchar_t* payload)
    {
        NativeToolkit::Notification::NotificationContent content;
        NotificationPayloadJson::Read(JsonObject::Parse(payload), content);

        const auto shown = g_manager->Show(content);
        Assert::IsTrue(shown.has_value(), L"the payload was rejected");

        return L"tag=" + g_backend->last.tag
             + L" group=" + g_backend->last.group
             + L" " + g_backend->last.xmlPayload;
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

    /// The error this payload's content comes back with.
    ///
    /// A value of the wrong shape throws while the helper reads it, which the
    /// 1.x C ABI reported as an HRESULT failure; everything after that is
    /// Manager::Show's answer.
    static DWORD ShowError(const wchar_t* payload)
    {
        NativeToolkit::Notification::NotificationContent content;
        try {
            NotificationPayloadJson::Read(JsonObject::Parse(payload), content);
        } catch (const winrt::hresult_error&) {
            return NOTIFICATION_ERROR_HRESULT_FAILURE;
        }

        const auto shown = g_manager->Show(content);
        return shown.has_value() ? NOTIFICATION_SUCCESS
                                 : static_cast<DWORD>(shown.error().code);
    }
};

}  // namespace WindowsNotificationPayloadTest
