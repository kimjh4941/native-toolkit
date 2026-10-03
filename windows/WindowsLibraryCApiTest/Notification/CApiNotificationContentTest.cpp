#include "pch.h"

#include "NativeToolkitC/Notification.h"

#include "Notification/NotificationCApiInternal.h"
#include "Notification/NotificationConvert.h"
#include "Notification/WindowsNotificationApiInternal.h"

#include <chrono>
#include <functional>
#include <optional>
#include <sstream>
#include <string>
#include <vector>

using namespace Microsoft::VisualStudio::CppUnitTestFramework;
using namespace NativeToolkitC::Detail::Notification;

// ============================================================================
// The notification content builder of the C ABI and the two operations that
// take content (stage 5 design, T-06).
//
// CT-11 compares what the C builder produces with the same content written
// directly in C++. The payload the OS receives is a function of the
// NotificationContent alone (BuildPayload, covered by the C++ API's tests), so
// equal contents give equal payloads; comparing the contents also names the
// field that differs. The fourteen rows of the input inventory's 1.10 are
// each checked both ways: given as "" and left out.
// ============================================================================

namespace CApiNotificationContentTest
{

namespace
{
    namespace Api = NativeToolkit::Notification;
    using NativeToolkit::Notification::Detail::TestAccess;

    // -- Comparing contents, naming the first difference ---------------------

    std::wstring Show(const std::optional<std::wstring>& value)
    {
        return value ? L"\"" + *value + L"\"" : L"(absent)";
    }

    std::wstring Show(const std::optional<Api::ArgumentPairs>& value)
    {
        if (!value) return L"(absent)";
        std::wstring text = L"{";
        for (const auto& [k, v] : *value) text += k + L"=" + v + L";";
        return text + L"}";
    }

    std::wstring Show(const std::wstring& value) { return L"\"" + value + L"\""; }

    template <class T>
    std::wstring Show(const T& value)
    {
        std::wstringstream text;
        text << static_cast<long long>(value);
        return text.str();
    }

    struct Differ {
        std::wstring first;

        template <class T>
        void Check(const wchar_t* field, const T& expected, const T& actual)
        {
            if (first.empty() && !(expected == actual)) {
                first = std::wstring(field) + L": expected " + Show(expected) + L", got " + Show(actual);
            }
        }
    };

    std::wstring Difference(const Api::NotificationContent& e, const Api::NotificationContent& a)
    {
        Differ d;
        d.Check(L"title", e.title, a.title);
        d.Check(L"body", e.body, a.body);
        d.Check(L"tag", e.tag, a.tag);
        d.Check(L"group", e.group, a.group);
        d.Check(L"scenario", static_cast<int>(e.scenario), static_cast<int>(a.scenario));
        d.Check(L"heroImage", e.heroImage, a.heroImage);
        d.Check(L"inlineImage", e.inlineImage, a.inlineImage);
        d.Check(L"appLogo present", e.appLogo.has_value(), a.appLogo.has_value());
        if (e.appLogo && a.appLogo) {
            d.Check(L"appLogo.uri", e.appLogo->uri, a.appLogo->uri);
            d.Check(L"appLogo.crop", static_cast<int>(e.appLogo->crop), static_cast<int>(a.appLogo->crop));
        }
        d.Check(L"attribution", e.attribution, a.attribution);
        d.Check(L"duration", static_cast<int>(e.duration), static_cast<int>(a.duration));
        d.Check(L"audio present", e.audio.has_value(), a.audio.has_value());
        if (e.audio && a.audio) {
            d.Check(L"audio.kind", static_cast<int>(e.audio->kind), static_cast<int>(a.audio->kind));
            d.Check(L"audio.eventName", e.audio->eventName, a.audio->eventName);
            d.Check(L"audio.uri", e.audio->uri, a.audio->uri);
            d.Check(L"audio.loop", e.audio->loop, a.audio->loop);
        }
        d.Check(L"buttons.size", e.buttons.size(), a.buttons.size());
        for (size_t i = 0; i < e.buttons.size() && i < a.buttons.size(); ++i) {
            d.Check(L"buttons[].label", e.buttons[i].label, a.buttons[i].label);
            d.Check(L"buttons[].args", e.buttons[i].args, a.buttons[i].args);
            d.Check(L"buttons[].invokeUri", e.buttons[i].invokeUri, a.buttons[i].invokeUri);
        }
        d.Check(L"textInputs.size", e.textInputs.size(), a.textInputs.size());
        for (size_t i = 0; i < e.textInputs.size() && i < a.textInputs.size(); ++i) {
            d.Check(L"textInputs[].id", e.textInputs[i].id, a.textInputs[i].id);
            d.Check(L"textInputs[].placeholder", e.textInputs[i].placeholder, a.textInputs[i].placeholder);
            d.Check(L"textInputs[].title", e.textInputs[i].title, a.textInputs[i].title);
        }
        d.Check(L"comboInputs.size", e.comboInputs.size(), a.comboInputs.size());
        for (size_t i = 0; i < e.comboInputs.size() && i < a.comboInputs.size(); ++i) {
            const auto& ec = e.comboInputs[i];
            const auto& ac = a.comboInputs[i];
            d.Check(L"comboInputs[].id", ec.id, ac.id);
            d.Check(L"comboInputs[].title", ec.title, ac.title);
            d.Check(L"comboInputs[].defaultSelection", ec.defaultSelection, ac.defaultSelection);
            d.Check(L"comboInputs[].items.size", ec.items.size(), ac.items.size());
            for (size_t j = 0; j < ec.items.size() && j < ac.items.size(); ++j) {
                d.Check(L"comboInputs[].items[].id", ec.items[j].id, ac.items[j].id);
                d.Check(L"comboInputs[].items[].label", ec.items[j].label, ac.items[j].label);
            }
        }
        d.Check(L"progress present", e.progress.has_value(), a.progress.has_value());
        if (e.progress && a.progress) {
            d.Check(L"progress.title", e.progress->title, a.progress->title);
            d.Check(L"progress.value", e.progress->value == a.progress->value, true);
            d.Check(L"progress.valueStr", e.progress->valueStr, a.progress->valueStr);
            d.Check(L"progress.status", e.progress->status, a.progress->status);
        }
        d.Check(L"timestamp present", e.timestamp.has_value(), a.timestamp.has_value());
        if (e.timestamp && a.timestamp) {
            d.Check(L"timestamp", e.timestamp->time_since_epoch().count(), a.timestamp->time_since_epoch().count());
        }
        d.Check(L"expiration present", e.expiration.has_value(), a.expiration.has_value());
        if (e.expiration && a.expiration) {
            d.Check(L"expiration", e.expiration->count(), a.expiration->count());
        }
        d.Check(L"expiresOnReboot", e.expiresOnReboot, a.expiresOnReboot);
        return d.first;
    }

    void AssertSame(const Api::NotificationContent& expected, const Api::NotificationContent& actual,
                    const std::wstring& context = L"")
    {
        const auto difference = Difference(expected, actual);
        if (!difference.empty()) {
            Assert::Fail((context.empty() ? difference : context + L": " + difference).c_str());
        }
    }

    // -- Building through the C ABI ------------------------------------------

    using Steps = std::function<void(ntk_notification_content*)>;

    void Ok(ntk_notification_error result)
    {
        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_NONE, result);
    }

    Api::NotificationContent Build(const Steps& steps)
    {
        ntk_notification_content* content = nullptr;
        Ok(ntk_notification_content_create(&content));
        steps(content);
        Api::NotificationContent built = content->content;
        ntk_notification_content_free(content);
        return built;
    }

    const char* const kBad = "\xFF";   // not UTF-8

    // -- A manager for show and schedule --------------------------------------

    Api::Result<Api::Manager> TestFactory(const Api::ManagerOptions&)
    {
        return TestAccess::MakeManager();
    }

    ntk_notification_manager* ClosedManager()
    {
        ntk_notification_manager_options options{};
        options.struct_size = static_cast<uint32_t>(sizeof(options));
        ntk_notification_manager* manager = nullptr;
        Ok(ntk_notification_manager_create(&options, &manager));
        ntk_notification_manager_close(manager);
        return manager;
    }
}

TEST_CLASS(CApiNotificationContentTest)
{
public:
    TEST_METHOD_INITIALIZE(SetUp)
    {
        SetManagerFactoryForTest(&TestFactory);
    }

    TEST_METHOD_CLEANUP(TearDown)
    {
        SetManagerFactoryForTest(nullptr);
    }

    // ------------------------------------------------------------------------
    // CT-11: the same content as C++
    // ------------------------------------------------------------------------

    TEST_METHOD(Test_NewContent_IsTheCppDefault)
    {
        AssertSame(Api::NotificationContent{}, Build([](ntk_notification_content*) {}));
    }

    TEST_METHOD(Test_EverySetter_BuildsTheSameContentAsCpp)
    {
        const auto built = Build([](ntk_notification_content* c) {
            Ok(ntk_notification_content_set_title(c, "Title"));
            Ok(ntk_notification_content_set_body(c, "Body \xE2\x9C\x93"));   // U+2713
            Ok(ntk_notification_content_set_tag(c, "tag"));
            Ok(ntk_notification_content_set_group(c, "group"));
            Ok(ntk_notification_content_set_scenario(c, NTK_NOTIFICATION_SCENARIO_INCOMING_CALL));
            Ok(ntk_notification_content_set_hero_image(c, "ms-appx:///hero.png"));
            Ok(ntk_notification_content_set_inline_image(c, "ms-appx:///inline.png"));
            Ok(ntk_notification_content_set_app_logo(c, "ms-appx:///logo.png", NTK_NOTIFICATION_LOGO_CROP_CIRCLE));
            Ok(ntk_notification_content_set_attribution(c, "via test"));
            Ok(ntk_notification_content_set_duration(c, NTK_NOTIFICATION_DURATION_LONG));
            Ok(ntk_notification_content_set_audio(c, NTK_NOTIFICATION_AUDIO_KIND_EVENT, "loopingAlarm", nullptr, 1));
            size_t index = 99;
            Ok(ntk_notification_content_add_button(c, "Reply", nullptr, 1, &index));
            Assert::AreEqual(size_t{0}, index);
            Ok(ntk_notification_content_add_button_argument(c, 0, "action", "reply"));
            Ok(ntk_notification_content_add_button_argument(c, 0, "empty", nullptr));
            Ok(ntk_notification_content_add_button(c, "Open", "https://example.com/", 0, &index));
            Assert::AreEqual(size_t{1}, index);
            Ok(ntk_notification_content_add_text_input(c, "text", "Type here", "Reply"));
            Ok(ntk_notification_content_add_combo(c, "pick", "Pick one", "b", &index));
            Assert::AreEqual(size_t{0}, index);
            Ok(ntk_notification_content_add_combo_item(c, 0, "a", "Apple"));
            Ok(ntk_notification_content_add_combo_item(c, 0, "b", "Banana"));
            Ok(ntk_notification_content_set_progress(c, "Upload", 0.5, "50%", "Uploading"));
            Ok(ntk_notification_content_set_timestamp(c, 1700000000123));
            Ok(ntk_notification_content_set_expiration(c, 3600));
            Ok(ntk_notification_content_set_expires_on_reboot(c, 1));
        });

        Api::NotificationContent expected;
        expected.title = L"Title";
        expected.body = std::wstring(L"Body ") + wchar_t(0x2713);
        expected.tag = L"tag";
        expected.group = L"group";
        expected.scenario = Api::Scenario::IncomingCall;
        expected.heroImage = L"ms-appx:///hero.png";
        expected.inlineImage = L"ms-appx:///inline.png";
        expected.appLogo = Api::AppLogo{L"ms-appx:///logo.png", Api::LogoCrop::Circle};
        expected.attribution = L"via test";
        expected.duration = Api::Duration::Long;
        Api::AudioSpec audio;
        audio.kind = Api::AudioKind::Event;
        audio.eventName = L"loopingAlarm";
        audio.loop = true;
        expected.audio = audio;
        expected.buttons.push_back({L"Reply", Api::ArgumentPairs{{L"action", L"reply"}, {L"empty", L""}}, std::nullopt});
        expected.buttons.push_back({L"Open", std::nullopt, L"https://example.com/"});
        expected.textInputs.push_back({L"text", L"Type here", L"Reply"});
        expected.comboInputs.push_back({L"pick", L"Pick one", L"b", {{L"a", L"Apple"}, {L"b", L"Banana"}}});
        expected.progress = Api::ProgressSpec{L"Upload", 0.5, L"50%", L"Uploading"};
        expected.timestamp = std::chrono::system_clock::time_point(std::chrono::milliseconds(1700000000123));
        expected.expiration = std::chrono::seconds(3600);
        expected.expiresOnReboot = true;

        AssertSame(expected, built);
    }

    TEST_METHOD(Test_EmptyAndAbsent_FollowTheInventory)
    {
        // Input inventory 1.10: rows 1 to 10 tell "" from absent, rows 11 to
        // 14 do not. Each row is built both ways and compared with C++.
        struct Row {
            const wchar_t* name;
            Steps withEmpty;
            Steps withNull;
            std::function<void(Api::NotificationContent&)> expectEmpty;
            std::function<void(Api::NotificationContent&)> expectNull;
        };
        using C = ntk_notification_content*;
        using N = Api::NotificationContent;
        const Row rows[] = {
            {L"1 title",
             [](C c) { Ok(ntk_notification_content_set_title(c, "")); },
             [](C c) { Ok(ntk_notification_content_set_title(c, nullptr)); },
             [](N& n) { n.title = L""; }, [](N&) {}},
            {L"2 body",
             [](C c) { Ok(ntk_notification_content_set_body(c, "")); },
             [](C c) { Ok(ntk_notification_content_set_body(c, nullptr)); },
             [](N& n) { n.body = L""; }, [](N&) {}},
            {L"3 attribution",
             [](C c) { Ok(ntk_notification_content_set_attribution(c, "")); },
             [](C c) { Ok(ntk_notification_content_set_attribution(c, nullptr)); },
             [](N& n) { n.attribution = L""; }, [](N&) {}},
            {L"4 progress.title",
             [](C c) { Ok(ntk_notification_content_set_progress(c, "", 0.0, nullptr, nullptr)); },
             [](C c) { Ok(ntk_notification_content_set_progress(c, nullptr, 0.0, nullptr, nullptr)); },
             [](N& n) { n.progress = Api::ProgressSpec{L"", 0.0, std::nullopt, std::nullopt}; },
             [](N& n) { n.progress = Api::ProgressSpec{}; }},
            {L"5 heroImage",
             [](C c) { Ok(ntk_notification_content_set_hero_image(c, "")); },
             [](C c) { Ok(ntk_notification_content_set_hero_image(c, nullptr)); },
             [](N& n) { n.heroImage = L""; }, [](N&) {}},
            {L"6 inlineImage",
             [](C c) { Ok(ntk_notification_content_set_inline_image(c, "")); },
             [](C c) { Ok(ntk_notification_content_set_inline_image(c, nullptr)); },
             [](N& n) { n.inlineImage = L""; }, [](N&) {}},
            {L"7 audio.uri",
             [](C c) { Ok(ntk_notification_content_set_audio(c, NTK_NOTIFICATION_AUDIO_KIND_URI, nullptr, "", 0)); },
             [](C c) { Ok(ntk_notification_content_set_audio(c, NTK_NOTIFICATION_AUDIO_KIND_URI, nullptr, nullptr, 0)); },
             [](N& n) { Api::AudioSpec a; a.kind = Api::AudioKind::Uri; a.uri = L""; n.audio = a; },
             [](N& n) { Api::AudioSpec a; a.kind = Api::AudioKind::Uri; n.audio = a; }},
            {L"8 buttons[].invokeUri",
             [](C c) { Ok(ntk_notification_content_add_button(c, "OK", "", 0, nullptr)); },
             [](C c) { Ok(ntk_notification_content_add_button(c, "OK", nullptr, 0, nullptr)); },
             [](N& n) { n.buttons.push_back({L"OK", std::nullopt, L""}); },
             [](N& n) { n.buttons.push_back({L"OK", std::nullopt, std::nullopt}); }},
            {L"9 textBoxes[].placeholder",
             [](C c) { Ok(ntk_notification_content_add_text_input(c, "id", "", nullptr)); },
             [](C c) { Ok(ntk_notification_content_add_text_input(c, "id", nullptr, nullptr)); },
             [](N& n) { n.textInputs.push_back({L"id", L"", std::nullopt}); },
             [](N& n) { n.textInputs.push_back({L"id", std::nullopt, std::nullopt}); }},
            {L"10 buttons[].args {} with invokeUri",
             [](C c) { Ok(ntk_notification_content_add_button(c, "OK", "u:x", 1, nullptr)); },
             [](C c) { Ok(ntk_notification_content_add_button(c, "OK", "u:x", 0, nullptr)); },
             [](N& n) { n.buttons.push_back({L"OK", Api::ArgumentPairs{}, L"u:x"}); },
             [](N& n) { n.buttons.push_back({L"OK", std::nullopt, L"u:x"}); }},
            {L"11 comboBoxes[].title",
             [](C c) { Ok(ntk_notification_content_add_combo(c, "id", "", nullptr, nullptr)); },
             [](C c) { Ok(ntk_notification_content_add_combo(c, "id", nullptr, nullptr, nullptr)); },
             [](N& n) { n.comboInputs.push_back({L"id", L"", L"", {}}); },
             [](N& n) { n.comboInputs.push_back({L"id", L"", L"", {}}); }},
            {L"12 comboBoxes[].defaultSelection",
             [](C c) { Ok(ntk_notification_content_add_combo(c, "id", nullptr, "", nullptr)); },
             [](C c) { Ok(ntk_notification_content_add_combo(c, "id", nullptr, nullptr, nullptr)); },
             [](N& n) { n.comboInputs.push_back({L"id", L"", L"", {}}); },
             [](N& n) { n.comboInputs.push_back({L"id", L"", L"", {}}); }},
            {L"13 tag and group",
             [](C c) { Ok(ntk_notification_content_set_tag(c, "")); Ok(ntk_notification_content_set_group(c, "")); },
             [](C c) { Ok(ntk_notification_content_set_tag(c, nullptr)); Ok(ntk_notification_content_set_group(c, nullptr)); },
             [](N&) {}, [](N&) {}},
            {L"14 audio.event",
             [](C c) { Ok(ntk_notification_content_set_audio(c, NTK_NOTIFICATION_AUDIO_KIND_EVENT, "", nullptr, 0)); },
             [](C c) { Ok(ntk_notification_content_set_audio(c, NTK_NOTIFICATION_AUDIO_KIND_EVENT, nullptr, nullptr, 0)); },
             [](N& n) { n.audio = Api::AudioSpec{}; }, [](N& n) { n.audio = Api::AudioSpec{}; }},
        };

        for (const auto& row : rows) {
            N empty, absent;
            row.expectEmpty(empty);
            row.expectNull(absent);
            AssertSame(empty, Build(row.withEmpty), std::wstring(row.name) + L" given as \"\"");
            AssertSame(absent, Build(row.withNull), std::wstring(row.name) + L" left out");
        }
    }

    TEST_METHOD(Test_OptionalFields_CanBeRemovedAgain)
    {
        const auto built = Build([](ntk_notification_content* c) {
            Ok(ntk_notification_content_set_title(c, "x"));
            Ok(ntk_notification_content_set_title(c, nullptr));
            Ok(ntk_notification_content_set_hero_image(c, "x"));
            Ok(ntk_notification_content_set_hero_image(c, nullptr));
            Ok(ntk_notification_content_set_app_logo(c, "x", NTK_NOTIFICATION_LOGO_CROP_NONE));
            Ok(ntk_notification_content_set_app_logo(c, nullptr, NTK_NOTIFICATION_LOGO_CROP_NONE));
        });
        AssertSame(Api::NotificationContent{}, built);
    }

    TEST_METHOD(Test_ButtonArgument_GivesTheButtonAnArgumentList)
    {
        const auto built = Build([](ntk_notification_content* c) {
            Ok(ntk_notification_content_add_button(c, "OK", nullptr, 0, nullptr));
            Ok(ntk_notification_content_add_button_argument(c, 0, "k", "v"));
        });
        Api::NotificationContent expected;
        expected.buttons.push_back({L"OK", Api::ArgumentPairs{{L"k", L"v"}}, std::nullopt});
        AssertSame(expected, built);
    }

    TEST_METHOD(Test_Timestamp_BeforeTheEpochAndAtTheLimits)
    {
        const int64_t limit = INT64_MAX / 10000;
        ntk_notification_content* c = nullptr;
        Ok(ntk_notification_content_create(&c));

        Ok(ntk_notification_content_set_timestamp(c, -86400000));
        Assert::AreEqual(-86400000LL, static_cast<long long>(std::chrono::duration_cast<std::chrono::milliseconds>(
                                          c->content.timestamp->time_since_epoch()).count()));
        Ok(ntk_notification_content_set_timestamp(c, limit));
        Ok(ntk_notification_content_set_timestamp(c, -limit));
        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_INVALID_PARAMETER, ntk_notification_content_set_timestamp(c, limit + 1));
        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_INVALID_PARAMETER, ntk_notification_content_set_timestamp(c, INT64_MIN));
        ntk_notification_content_free(c);
    }

    // ------------------------------------------------------------------------
    // CT-05, CT-06: what the builder refuses, and that it then changes nothing
    // ------------------------------------------------------------------------

    TEST_METHOD(Test_NullContent_IsInvalidForEverySetter)
    {
        const int32_t invalid = NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;
        ntk_notification_content* n = nullptr;
        Assert::AreEqual(invalid, ntk_notification_content_create(nullptr));
        Assert::AreEqual(invalid, ntk_notification_content_set_title(n, "x"));
        Assert::AreEqual(invalid, ntk_notification_content_set_body(n, "x"));
        Assert::AreEqual(invalid, ntk_notification_content_set_tag(n, "x"));
        Assert::AreEqual(invalid, ntk_notification_content_set_group(n, "x"));
        Assert::AreEqual(invalid, ntk_notification_content_set_scenario(n, 0));
        Assert::AreEqual(invalid, ntk_notification_content_set_hero_image(n, "x"));
        Assert::AreEqual(invalid, ntk_notification_content_set_inline_image(n, "x"));
        Assert::AreEqual(invalid, ntk_notification_content_set_app_logo(n, "x", 0));
        Assert::AreEqual(invalid, ntk_notification_content_set_attribution(n, "x"));
        Assert::AreEqual(invalid, ntk_notification_content_set_duration(n, 0));
        Assert::AreEqual(invalid, ntk_notification_content_set_audio(n, 0, nullptr, nullptr, 0));
        Assert::AreEqual(invalid, ntk_notification_content_add_button(n, "x", nullptr, 0, nullptr));
        Assert::AreEqual(invalid, ntk_notification_content_add_button_argument(n, 0, "k", "v"));
        Assert::AreEqual(invalid, ntk_notification_content_add_text_input(n, "x", nullptr, nullptr));
        Assert::AreEqual(invalid, ntk_notification_content_add_combo(n, "x", nullptr, nullptr, nullptr));
        Assert::AreEqual(invalid, ntk_notification_content_add_combo_item(n, 0, "x", "y"));
        Assert::AreEqual(invalid, ntk_notification_content_set_progress(n, nullptr, 0.0, nullptr, nullptr));
        Assert::AreEqual(invalid, ntk_notification_content_set_timestamp(n, 0));
        Assert::AreEqual(invalid, ntk_notification_content_set_expiration(n, 0));
        Assert::AreEqual(invalid, ntk_notification_content_set_expires_on_reboot(n, 0));
        ntk_notification_content_free(nullptr);
    }

    TEST_METHOD(Test_RefusedInput_LeavesTheContentAsItWas)
    {
        using Setter = std::function<ntk_notification_error(ntk_notification_content*)>;
        struct Case {
            const wchar_t* name;
            Setter call;
        };
        const Case cases[] = {
            {L"bad title", [](auto c) { return ntk_notification_content_set_title(c, kBad); }},
            {L"bad body", [](auto c) { return ntk_notification_content_set_body(c, kBad); }},
            {L"bad tag", [](auto c) { return ntk_notification_content_set_tag(c, kBad); }},
            {L"bad group", [](auto c) { return ntk_notification_content_set_group(c, kBad); }},
            {L"scenario -1", [](auto c) { return ntk_notification_content_set_scenario(c, -1); }},
            {L"scenario 5", [](auto c) { return ntk_notification_content_set_scenario(c, 5); }},
            {L"bad hero", [](auto c) { return ntk_notification_content_set_hero_image(c, kBad); }},
            {L"bad inline", [](auto c) { return ntk_notification_content_set_inline_image(c, kBad); }},
            {L"bad logo", [](auto c) { return ntk_notification_content_set_app_logo(c, kBad, 0); }},
            {L"crop 2", [](auto c) { return ntk_notification_content_set_app_logo(c, "x", 2); }},
            {L"crop 2 without uri", [](auto c) { return ntk_notification_content_set_app_logo(c, nullptr, 2); }},
            {L"bad attribution", [](auto c) { return ntk_notification_content_set_attribution(c, kBad); }},
            {L"duration 2", [](auto c) { return ntk_notification_content_set_duration(c, 2); }},
            {L"audio kind 3", [](auto c) { return ntk_notification_content_set_audio(c, 3, nullptr, nullptr, 0); }},
            {L"bad audio event", [](auto c) { return ntk_notification_content_set_audio(c, 0, kBad, nullptr, 0); }},
            {L"bad audio uri", [](auto c) { return ntk_notification_content_set_audio(c, 2, nullptr, kBad, 0); }},
            {L"button without label", [](auto c) { return ntk_notification_content_add_button(c, nullptr, nullptr, 0, nullptr); }},
            {L"bad button label", [](auto c) { return ntk_notification_content_add_button(c, kBad, nullptr, 0, nullptr); }},
            {L"bad button uri", [](auto c) { return ntk_notification_content_add_button(c, "x", kBad, 0, nullptr); }},
            {L"argument index", [](auto c) { return ntk_notification_content_add_button_argument(c, 1, "k", "v"); }},
            {L"argument without key", [](auto c) { return ntk_notification_content_add_button_argument(c, 0, nullptr, "v"); }},
            {L"bad argument value", [](auto c) { return ntk_notification_content_add_button_argument(c, 0, "k", kBad); }},
            {L"text input without id", [](auto c) { return ntk_notification_content_add_text_input(c, nullptr, nullptr, nullptr); }},
            {L"bad text input title", [](auto c) { return ntk_notification_content_add_text_input(c, "x", nullptr, kBad); }},
            {L"combo without id", [](auto c) { return ntk_notification_content_add_combo(c, nullptr, nullptr, nullptr, nullptr); }},
            {L"bad combo default", [](auto c) { return ntk_notification_content_add_combo(c, "x", nullptr, kBad, nullptr); }},
            {L"combo index", [](auto c) { return ntk_notification_content_add_combo_item(c, 1, "x", "y"); }},
            {L"combo item without id", [](auto c) { return ntk_notification_content_add_combo_item(c, 0, nullptr, "y"); }},
            {L"combo item without label", [](auto c) { return ntk_notification_content_add_combo_item(c, 0, "x", nullptr); }},
            {L"bad progress status", [](auto c) { return ntk_notification_content_set_progress(c, nullptr, 0.0, nullptr, kBad); }},
            {L"timestamp out of range", [](auto c) { return ntk_notification_content_set_timestamp(c, INT64_MAX); }},
        };

        for (const auto& test : cases) {
            ntk_notification_content* c = nullptr;
            Ok(ntk_notification_content_create(&c));
            Ok(ntk_notification_content_set_title(c, "kept"));
            Ok(ntk_notification_content_add_button(c, "kept", nullptr, 0, nullptr));
            Ok(ntk_notification_content_add_combo(c, "kept", nullptr, nullptr, nullptr));
            const Api::NotificationContent before = c->content;

            Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_INVALID_PARAMETER, test.call(c), test.name);
            AssertSame(before, c->content, test.name);
            ntk_notification_content_free(c);
        }
    }

    TEST_METHOD(Test_SystemCode_IsZeroAfterASetter)
    {
        ntk_notification_content* c = nullptr;
        Ok(ntk_notification_content_create(&c));
        ntk_notification_content_set_title(c, kBad);
        Ok(ntk_notification_content_set_title(c, "ok"));
        Assert::AreEqual(0u, ntk_last_system_code());
        ntk_notification_content_free(c);
    }

    // ------------------------------------------------------------------------
    // Show and schedule (OP-10, OP-11)
    // ------------------------------------------------------------------------

    TEST_METHOD(Test_ShowAndSchedule_NullArguments_AreInvalid)
    {
        auto* manager = ClosedManager();
        ntk_notification_content* c = nullptr;
        Ok(ntk_notification_content_create(&c));
        const int32_t invalid = NTK_NOTIFICATION_ERROR_INVALID_PARAMETER;

        Assert::AreEqual(invalid, ntk_notification_show(nullptr, c));
        Assert::AreEqual(invalid, ntk_notification_show(manager, nullptr));
        Assert::AreEqual(invalid, ntk_notification_schedule(nullptr, c, 0));
        Assert::AreEqual(invalid, ntk_notification_schedule(manager, nullptr, 0));
        Assert::AreEqual(invalid, ntk_notification_schedule(manager, c, INT64_MAX));

        ntk_notification_content_free(c);
        ntk_notification_manager_free(manager);
    }

    TEST_METHOD(Test_ShowAndSchedule_OnAClosedManager_AreNotInitialized)
    {
        auto* manager = ClosedManager();
        ntk_notification_content* c = nullptr;
        Ok(ntk_notification_content_create(&c));
        Ok(ntk_notification_content_set_title(c, "x"));

        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_NOT_INITIALIZED, ntk_notification_show(manager, c));
        Assert::AreEqual<int32_t>(NTK_NOTIFICATION_ERROR_NOT_INITIALIZED, ntk_notification_schedule(manager, c, 1700000000000));
        // show does not change the content it is given.
        Assert::AreEqual(std::wstring(L"x"), *c->content.title);

        ntk_notification_content_free(c);
        ntk_notification_manager_free(manager);
    }
};

}  // namespace CApiNotificationContentTest
