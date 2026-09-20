#include "pch.h"
#include "Notification/Domain/WindowsNotificationValidation.h"
#include "Notification/WindowsNotificationManagerInternal.h"
#include <winrt/Windows.Data.Json.h>

using namespace Microsoft::VisualStudio::CppUnitTestFramework;
using namespace winrt::Windows::Data::Json;

// ============================================================================
// T-07 of the stage 3 design: the payload rules have to give the same answer
// whether they are applied to the JSON payload of the C ABI or to the struct
// of the C++ API.
//
// Each case below is written twice - once as JSON through ValidatePayload, once
// as a NotificationContent through the Domain rules - and the two are asserted
// to agree. Checking only the struct would let the two drift apart, which is
// exactly the regression T-14 has to avoid when it puts the C ABI on top of
// the C++ API.
// ============================================================================

namespace WindowsNotificationValidationDomainTest
{

namespace Domain = NativeToolkit::Notification::Domain;
using namespace NativeToolkit::Notification;

namespace
{
    Button ButtonWithArgs(std::wstring label)
    {
        Button button;
        button.label = std::move(label);
        button.args.emplace_back(L"action", L"open");
        return button;
    }
}

TEST_CLASS(NotificationValidationDomainTest)
{
    /// Runs the JSON rules the way Show does today. This has to be a member:
    /// the manager befriends the class, not the file.
    static bool JsonIsValid(const wchar_t* payload)
    {
        JsonObject json = JsonObject::Parse(payload);
        DWORD error = 0;
        return WindowsNotificationManager::GetInstance().ValidatePayload(json, &error);
    }

public:

    TEST_METHOD(Test_EmptyPayload_IsValidBothWays)
    {
        Assert::IsTrue(JsonIsValid(LR"({"title":"hello"})"));
        NotificationContent content;
        content.title = L"hello";
        Assert::IsTrue(Domain::IsValid(content));
    }

    TEST_METHOD(Test_FiveButtons_AreAllowedBothWays)
    {
        Assert::IsTrue(JsonIsValid(LR"({"buttons":[{"label":"1"},{"label":"2"},{"label":"3"},{"label":"4"},{"label":"5"}]})"));

        NotificationContent content;
        for (int i = 0; i < 5; ++i) content.buttons.push_back(Button{L"b"});
        Assert::IsTrue(Domain::IsValid(content));
    }

    TEST_METHOD(Test_SixButtons_AreRejectedBothWays)
    {
        Assert::IsFalse(JsonIsValid(LR"({"buttons":[{"label":"1"},{"label":"2"},{"label":"3"},{"label":"4"},{"label":"5"},{"label":"6"}]})"));

        NotificationContent content;
        for (int i = 0; i < 6; ++i) content.buttons.push_back(Button{L"b"});
        Assert::IsFalse(Domain::IsValid(content));
        Assert::IsTrue(Domain::ValidationFailure::TooManyButtons == Domain::FindFailure(content));
    }

    TEST_METHOD(Test_LoopingAudioWithoutLongDuration_IsRejectedBothWays)
    {
        Assert::IsFalse(JsonIsValid(LR"({"audio":{"loop":true}})"));

        NotificationContent content;
        content.audio.loop = true;            // duration stays Short
        Assert::IsFalse(Domain::IsValid(content));
        Assert::IsTrue(Domain::ValidationFailure::LoopingAudioNeedsLongDuration == Domain::FindFailure(content));
    }

    TEST_METHOD(Test_LoopingAudioWithLongDuration_IsAllowedBothWays)
    {
        Assert::IsTrue(JsonIsValid(LR"({"duration":"long","audio":{"loop":true}})"));

        NotificationContent content;
        content.duration   = Duration::Long;
        content.audio.loop = true;
        Assert::IsTrue(Domain::IsValid(content));
    }

    TEST_METHOD(Test_ButtonWithArgsAndInvokeUri_IsRejectedBothWays)
    {
        Assert::IsFalse(JsonIsValid(LR"({"buttons":[{"label":"open","args":{"a":"b"},"invokeUri":"https://example.com"}]})"));

        NotificationContent content;
        Button button = ButtonWithArgs(L"open");
        button.invokeUri = L"https://example.com";
        content.buttons.push_back(button);
        Assert::IsFalse(Domain::IsValid(content));
        Assert::IsTrue(Domain::ValidationFailure::ButtonHasArgsAndInvokeUri == Domain::FindFailure(content));
    }

    TEST_METHOD(Test_ButtonWithOnlyOneOfThem_IsAllowedBothWays)
    {
        Assert::IsTrue(JsonIsValid(LR"({"buttons":[{"label":"open","args":{"a":"b"}}]})"));
        Assert::IsTrue(JsonIsValid(LR"({"buttons":[{"label":"open","invokeUri":"https://example.com"}]})"));

        NotificationContent withArgs;
        withArgs.buttons.push_back(ButtonWithArgs(L"open"));
        Assert::IsTrue(Domain::IsValid(withArgs));

        NotificationContent withUri;
        Button uriButton;
        uriButton.label = L"open";
        uriButton.invokeUri = L"https://example.com";
        withUri.buttons.push_back(uriButton);
        Assert::IsTrue(Domain::IsValid(withUri));
    }

    // --- Rules the JSON path enforces while building, not in ValidatePayload --

    TEST_METHOD(Test_AudioUriKindWithoutUri_IsRejected)
    {
        // ApplyAudio rejects audio.type=uri with no uri; the struct says the
        // same before anything is built.
        NotificationContent content;
        content.audio.kind = AudioKind::Uri;

        Assert::IsFalse(Domain::IsValid(content));
        Assert::IsTrue(Domain::ValidationFailure::AudioUriMissing == Domain::FindFailure(content));

        content.audio.uri = L"ms-appx:///sound.wav";
        Assert::IsTrue(Domain::IsValid(content));
    }

    // --- Badge, which is not part of the payload ----------------------------

    TEST_METHOD(Test_BadgeValues_MatchTheCAbiRange)
    {
        // Positive is a count, zero clears, -1..-6 name glyphs, below that is
        // not a badge (NTF-65).
        Assert::IsTrue(Domain::IsValidBadgeValue(5));
        Assert::IsTrue(Domain::IsValidBadgeValue(0));
        Assert::IsTrue(Domain::IsValidBadgeValue(-6));
        Assert::IsFalse(Domain::IsValidBadgeValue(-7));
        Assert::IsFalse(Domain::IsValidBadgeValue(-100));
    }

    TEST_METHOD(Test_Validate_ReportsInvalidParameter)
    {
        NotificationContent content;
        content.audio.loop = true;

        const auto result = Domain::Validate(content);

        Assert::IsFalse(result.has_value());
        Assert::IsTrue(ErrorCode::InvalidParameter == result.error().code);
    }
};

}  // namespace WindowsNotificationValidationDomainTest
