#include "pch.h"
#include "Notification/Data/WindowsClassicActivator.h"
#include "Notification/WindowsNotificationManagerInternal.h"
#include "Notification/Data/WindowsNotificationBuilder.h"
#include "Support/NotificationPayloadJson.h"

#include "Support/AppSdkRuntimeForTest.h"

using namespace Microsoft::VisualStudio::CppUnitTestFramework;
using namespace winrt::Windows::Data::Json;

// ============================================================================
// U-E of the stage 3 design, for the Data layer of the notification feature.
//
// There are two ways to describe a toast: the JSON payload the C ABI takes and
// the NotificationContent a C++ caller writes. One builder now serves both, so
// what is left to go wrong is the reading: a payload whose key lands in the
// wrong field, or in no field at all, would build a poorer toast that no
// caller of the C ABI would ever notice.
//
// So every test here describes the same notification twice - once as the
// payload, once as the content a reader of the documentation would write - and
// compares the toast each produces. A key the parser forgets shows up as a
// difference in the XML rather than as a missing feature in the product.
// ============================================================================

namespace WindowsNotificationBuilderTest
{

namespace Data = NativeToolkit::Notification::Data;
using namespace NativeToolkit::Notification;

TEST_CLASS(NotificationBuilderTest)
{
public:

    TEST_CLASS_INITIALIZE(StartRuntime)
    {
        // Building a toast activates App SDK types, so the runtime has to be
        // there. Only this class and NotificationApiTest need it.
        const std::wstring& failure = AppSdkRuntimeForTest::Ensure();
        if (!failure.empty()) {
            Assert::Fail(failure.c_str());
        }
    }

    // --- Text and identity --------------------------------------------------

    TEST_METHOD(Test_TitleAndBody_MatchTheJsonPath)
    {
        NotificationContent content;
        content.title = L"Build finished";
        content.body  = L"3 warnings";

        AssertSameXml(LR"({"title":"Build finished","body":"3 warnings"})", content);
    }

    TEST_METHOD(Test_TagAndGroup_MatchTheJsonPath)
    {
        NotificationContent content;
        content.title = L"t";
        content.tag   = L"job-42";
        content.group = L"builds";

        AssertSameXml(LR"({"title":"t","tag":"job-42","group":"builds"})", content);
    }

    // --- Scenario and duration ----------------------------------------------

    TEST_METHOD(Test_EveryScenario_MatchesTheJsonPath)
    {
        AssertScenario(L"reminder", Scenario::Reminder);
        AssertScenario(L"alarm", Scenario::Alarm);
        AssertScenario(L"urgent", Scenario::Urgent);
        AssertScenario(L"incomingCall", Scenario::IncomingCall);
    }

    TEST_METHOD(Test_DefaultScenario_SetsNothing)
    {
        // Scenario::Default has to mean "no scenario key", not "the reminder
        // scenario with default settings".
        NotificationContent content;
        content.title = L"t";

        AssertSameXml(LR"({"title":"t"})", content);
    }

    TEST_METHOD(Test_LongDuration_MatchesTheJsonPath)
    {
        NotificationContent content;
        content.title    = L"t";
        content.duration = Duration::Long;

        AssertSameXml(LR"({"title":"t","duration":"long"})", content);
    }

    // --- Buttons ------------------------------------------------------------

    TEST_METHOD(Test_ButtonWithArguments_MatchesTheJsonPath)
    {
        NotificationContent content;
        content.title = L"t";
        Button button;
        button.label = L"Open";
        button.args  = ArgumentPairs{{L"action", L"open"}, {L"id", L"42"}};
        content.buttons.push_back(button);

        AssertSameXml(
            LR"({"title":"t","buttons":[{"label":"Open","args":{"action":"open","id":"42"}}]})",
            content);
    }

    TEST_METHOD(Test_ButtonWithInvokeUri_MatchesTheJsonPath)
    {
        NotificationContent content;
        content.title = L"t";
        Button button;
        button.label     = L"Docs";
        button.invokeUri = L"https://example.com/docs";
        content.buttons.push_back(button);

        AssertSameXml(
            LR"({"title":"t","buttons":[{"label":"Docs","invokeUri":"https://example.com/docs"}]})",
            content);
    }

    TEST_METHOD(Test_FiveButtons_MatchTheJsonPath)
    {
        // The maximum the validation allows, so the order of a full row is
        // covered rather than just one button.
        NotificationContent content;
        content.title = L"t";
        std::wstring json = LR"({"title":"t","buttons":[)";
        for (int i = 1; i <= 5; ++i) {
            const std::wstring label = L"b" + std::to_wstring(i);
            Button button;
            button.label = label;
            button.args  = ArgumentPairs{{L"n", std::to_wstring(i)}};
            content.buttons.push_back(button);

            if (i > 1) json += L",";
            json += LR"({"label":")" + label + LR"(","args":{"n":")" + std::to_wstring(i) + LR"("}})";
        }
        json += L"]}";

        AssertSameXml(json.c_str(), content);
    }

    // --- Inputs -------------------------------------------------------------

    TEST_METHOD(Test_BareTextBox_MatchesTheJsonPath)
    {
        // With neither placeholder nor title the one-argument overload is the
        // one the JSON path picks, and it produces different XML.
        NotificationContent content;
        content.title = L"t";
        content.textInputs.push_back(TextInput{L"reply"});

        AssertSameXml(LR"({"title":"t","textBoxes":[{"id":"reply"}]})", content);
    }

    TEST_METHOD(Test_TextBoxWithPlaceholderAndTitle_MatchesTheJsonPath)
    {
        NotificationContent content;
        content.title = L"t";
        content.textInputs.push_back(TextInput{L"reply", L"Type here", L"Your answer"});

        AssertSameXml(
            LR"({"title":"t","textBoxes":[{"id":"reply","placeholder":"Type here","title":"Your answer"}]})",
            content);
    }

    TEST_METHOD(Test_ComboBox_MatchesTheJsonPath)
    {
        NotificationContent content;
        content.title = L"t";
        ComboInput combo;
        combo.id               = L"when";
        combo.title            = L"Remind me";
        combo.defaultSelection = L"later";
        combo.items            = {ComboItem{L"now", L"Now"}, ComboItem{L"later", L"In an hour"}};
        content.comboInputs.push_back(combo);

        AssertSameXml(
            LR"({"title":"t","comboBoxes":[{"id":"when","title":"Remind me","defaultSelection":"later",)"
            LR"("items":[{"id":"now","label":"Now"},{"id":"later","label":"In an hour"}]}]})",
            content);
    }

    // --- Images -------------------------------------------------------------

    TEST_METHOD(Test_AppLogoCircleCrop_MatchesTheJsonPath)
    {
        NotificationContent content;
        content.title   = L"t";
        content.appLogo = AppLogo{L"https://example.com/logo.png", LogoCrop::Circle};

        AssertSameXml(
            LR"({"title":"t","appLogo":{"uri":"https://example.com/logo.png","crop":"circle"}})",
            content);
    }

    TEST_METHOD(Test_AppLogoWithoutCrop_MatchesTheJsonPath)
    {
        NotificationContent content;
        content.title   = L"t";
        content.appLogo = AppLogo{L"https://example.com/logo.png", LogoCrop::None};

        AssertSameXml(LR"({"title":"t","appLogo":{"uri":"https://example.com/logo.png"}})", content);
    }

    TEST_METHOD(Test_HeroAndInlineImages_MatchTheJsonPath)
    {
        NotificationContent content;
        content.title       = L"t";
        content.heroImage   = L"https://example.com/hero.png";
        content.inlineImage = L"https://example.com/inline.png";

        AssertSameXml(
            LR"({"title":"t","heroImage":"https://example.com/hero.png",)"
            LR"("inlineImage":"https://example.com/inline.png"})",
            content);
    }

    // --- Audio --------------------------------------------------------------

    TEST_METHOD(Test_NoAudio_SetsNothing)
    {
        // An absent audio object leaves the sound to the OS. The struct says
        // that with an empty optional, not with a default-constructed
        // AudioSpec, which would name the default sound explicitly.
        NotificationContent content;
        content.title = L"t";

        AssertSameXml(LR"({"title":"t"})", content);
    }

    TEST_METHOD(Test_EverySoundEvent_MatchesTheJsonPath)
    {
        AssertSoundEvent(L"reminder");
        AssertSoundEvent(L"alarm");
        AssertSoundEvent(L"loopingAlarm");
        AssertSoundEvent(L"loopingCall");
        AssertSoundEvent(L"somethingUnknown");  // both fall back to the default sound
    }

    TEST_METHOD(Test_LoopingAudio_MatchesTheJsonPath)
    {
        NotificationContent content;
        content.title    = L"t";
        content.duration = Duration::Long;
        AudioSpec audio;
        audio.eventName = L"loopingAlarm";
        audio.loop      = true;
        content.audio   = audio;

        AssertSameXml(
            LR"({"title":"t","duration":"long","audio":{"event":"loopingAlarm","loop":true}})",
            content);
    }

    TEST_METHOD(Test_AudioUri_MatchesTheJsonPath)
    {
        NotificationContent content;
        content.title = L"t";
        AudioSpec audio;
        audio.kind    = AudioKind::Uri;
        audio.uri     = L"ms-appx:///Assets/ping.wav";
        content.audio = audio;

        AssertSameXml(
            LR"({"title":"t","audio":{"type":"uri","uri":"ms-appx:///Assets/ping.wav"}})", content);
    }

    TEST_METHOD(Test_MutedAudio_DiscardsTheRest)
    {
        // NTF-15: mute returns before loop and the event are read, so a muted
        // notification that also asks for a looping alarm is simply silent.
        // The struct path has to lose them in the same place.
        NotificationContent content;
        content.title    = L"t";
        content.duration = Duration::Long;
        AudioSpec audio;
        audio.kind      = AudioKind::Mute;
        audio.eventName = L"loopingAlarm";
        audio.loop      = true;
        content.audio   = audio;

        AssertSameXml(
            LR"({"title":"t","duration":"long",)"
            LR"("audio":{"type":"mute","event":"loopingAlarm","loop":true}})",
            content);
    }

    // --- Progress -----------------------------------------------------------

    TEST_METHOD(Test_ProgressWithEverything_MatchesTheJsonPath)
    {
        NotificationContent content;
        content.title = L"t";
        ProgressSpec progress;
        progress.title    = L"Downloading";
        progress.value    = 0.4;
        progress.valueStr = L"40%";
        progress.status   = L"Working";
        content.progress  = progress;

        AssertSameXml(
            LR"({"title":"t","progress":{"title":"Downloading","value":0.4,)"
            LR"("valueStr":"40%","status":"Working"}})",
            content);
    }

    TEST_METHOD(Test_ProgressWithoutValueStringOrStatus_BindsNeither)
    {
        // It is the presence of the key that decides whether the bar binds
        // those parts, which is why they are optional rather than empty.
        NotificationContent content;
        content.title = L"t";
        ProgressSpec progress;
        progress.value   = 0.4;
        content.progress = progress;

        AssertSameXml(LR"({"title":"t","progress":{"value":0.4}})", content);
    }

    // --- Attribution and timestamp ------------------------------------------

    TEST_METHOD(Test_Attribution_MatchesTheJsonPath)
    {
        NotificationContent content;
        content.title       = L"t";
        content.attribution = L"via Native Toolkit";

        AssertSameXml(LR"({"title":"t","attribution":"via Native Toolkit"})", content);
    }

    TEST_METHOD(Test_Timestamp_MatchesTheJsonPath)
    {
        // The JSON carries unix seconds; the struct carries a time_point. The
        // same instant has to reach the toast either way.
        const time_t unixSeconds = 1700000000;

        NotificationContent content;
        content.title     = L"t";
        content.timestamp = std::chrono::system_clock::from_time_t(unixSeconds);

        AssertSameXml(LR"({"title":"t","timestamp":1700000000})", content);
    }

    // --- Everything at once -------------------------------------------------

    TEST_METHOD(Test_FullNotification_MatchesTheJsonPath)
    {
        // The order in which the parts are applied is part of the output, so
        // one notification that uses all of them guards against a rearranged
        // build that each single-field test would still pass.
        NotificationContent content;
        content.title       = L"Backup complete";
        content.body        = L"1,204 files";
        content.tag         = L"backup";
        content.group       = L"jobs";
        content.scenario    = Scenario::Reminder;
        content.duration    = Duration::Long;
        content.heroImage   = L"https://example.com/hero.png";
        content.inlineImage = L"https://example.com/inline.png";
        content.appLogo     = AppLogo{L"https://example.com/logo.png", LogoCrop::Circle};
        content.attribution = L"Native Toolkit";
        content.timestamp   = std::chrono::system_clock::from_time_t(1700000000);

        Button open;
        open.label = L"Open";
        open.args  = ArgumentPairs{{L"action", L"open"}};
        Button docs;
        docs.label     = L"Docs";
        docs.invokeUri = L"https://example.com/docs";
        content.buttons = {open, docs};

        content.textInputs.push_back(TextInput{L"note", L"Add a note", L"Note"});
        ComboInput combo;
        combo.id               = L"when";
        combo.title            = L"Remind me";
        combo.defaultSelection = L"later";
        combo.items            = {ComboItem{L"now", L"Now"}, ComboItem{L"later", L"In an hour"}};
        content.comboInputs.push_back(combo);

        AudioSpec audio;
        audio.eventName = L"loopingAlarm";
        audio.loop      = true;
        content.audio   = audio;

        ProgressSpec progress;
        progress.title    = L"Uploading";
        progress.value    = 0.75;
        progress.valueStr = L"75%";
        progress.status   = L"Almost there";
        content.progress  = progress;

        AssertSameXml(
            LR"({"title":"Backup complete","body":"1,204 files","tag":"backup","group":"jobs",)"
            LR"("scenario":"reminder","duration":"long",)"
            LR"("buttons":[{"label":"Open","args":{"action":"open"}},)"
            LR"({"label":"Docs","invokeUri":"https://example.com/docs"}],)"
            LR"("textBoxes":[{"id":"note","placeholder":"Add a note","title":"Note"}],)"
            LR"("comboBoxes":[{"id":"when","title":"Remind me","defaultSelection":"later",)"
            LR"("items":[{"id":"now","label":"Now"},{"id":"later","label":"In an hour"}]}],)"
            LR"("appLogo":{"uri":"https://example.com/logo.png","crop":"circle"},)"
            LR"("heroImage":"https://example.com/hero.png",)"
            LR"("inlineImage":"https://example.com/inline.png",)"
            LR"("audio":{"event":"loopingAlarm","loop":true},)"
            LR"("progress":{"title":"Uploading","value":0.75,"valueStr":"75%","status":"Almost there"},)"
            LR"("attribution":"Native Toolkit","timestamp":1700000000})",
            content);
    }

private:

    /// Everything the builder produced, as one comparable string.
    ///
    /// The payload XML carries most of it, but the tag and the group are
    /// properties of the notification rather than of its XML, so comparing the
    /// payload alone would let those two be forgotten without a test noticing.
    static std::wstring Describe(
        const winrt::Microsoft::Windows::AppNotifications::AppNotification& notification)
    {
        return L"tag=" + std::wstring{notification.Tag()}
             + L" group=" + std::wstring{notification.Group()}
             + L" " + std::wstring{notification.Payload()};
    }

    /// The toast the C ABI would deliver for this payload, by the route it
    /// takes now: the bridge reads it into a content and the same builder
    /// turns that into a toast.
    static std::wstring FromJson(const wchar_t* payload)
    {
        NotificationContent parsed;
        NotificationPayloadJson::Read(JsonObject::Parse(payload), parsed);
        return FromContent(parsed);
    }

    /// The toast the C++ API would deliver for this content.
    static std::wstring FromContent(const NotificationContent& content)
    {
        auto builder = Data::BuildFromContent(content);
        return Describe(builder.BuildNotification());
    }

    /// Both descriptions have to reach the same toast.
    static void AssertSameXml(const wchar_t* payload, const NotificationContent& content)
    {
        Assert::AreEqual(FromJson(payload), FromContent(content));
    }

    static void AssertScenario(const wchar_t* name, Scenario scenario)
    {
        NotificationContent content;
        content.title    = L"t";
        content.scenario = scenario;

        const std::wstring json = std::wstring(LR"({"title":"t","scenario":")") + name + LR"("})";
        AssertSameXml(json.c_str(), content);
    }

    static void AssertSoundEvent(const wchar_t* name)
    {
        NotificationContent content;
        content.title = L"t";
        AudioSpec audio;
        audio.eventName = name;
        content.audio   = audio;

        const std::wstring json = std::wstring(LR"({"title":"t","audio":{"event":")") + name + LR"("}})";
        AssertSameXml(json.c_str(), content);
    }
};

}  // namespace WindowsNotificationBuilderTest
