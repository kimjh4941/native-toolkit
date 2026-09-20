/**
 * @file WindowsNotificationActivation.h
 * @brief Data layer: what the user did, as the C++ API sees it.
 * @details
 *  Both activation paths - the AppNotificationManager event of a packaged app
 *  and the COM activator of an unpackaged one - end up handing the manager one
 *  flat JSON object of strings: the arguments of the button that was pressed,
 *  merged with the contents of every text and selection field. That object is
 *  what this turns into an ActivationArgs.
 *
 *  rawArguments therefore holds that JSON rather than the query string the
 *  unpackaged activator started from. The implementation does not keep the
 *  query string, and inventing one here would be a worse answer than naming
 *  what is actually available.
 */
#pragma once

#include <winrt/Windows.Data.Json.h>

#include <string>

#include "NativeToolkit/Notification.h"

namespace NativeToolkit::Notification::Data {

/**
 * @brief Turns the activation JSON into the values a handler receives.
 * @details Anything that is not a JSON object of strings yields no pairs; the
 *          raw text is still passed on, so nothing the OS sent is lost.
 */
inline ActivationArgs ParseActivationJson(const std::wstring& json)
{
    using winrt::Windows::Data::Json::JsonObject;
    using winrt::Windows::Data::Json::JsonValueType;

    ActivationArgs args;
    args.rawArguments = json;

    JsonObject root{nullptr};
    if (!JsonObject::TryParse(winrt::hstring{json}, root)) {
        return args;
    }
    for (const auto& entry : root) {
        if (entry.Value().ValueType() != JsonValueType::String) {
            continue;
        }
        args.values.emplace_back(std::wstring{entry.Key()}, std::wstring{entry.Value().GetString()});
    }
    return args;
}

}  // namespace NativeToolkit::Notification::Data
