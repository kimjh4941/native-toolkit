/**
 * @file NotificationPayloadJson.h
 * @brief Test helper: reads the 1.x C ABI's notification payload into the C++
 *        API's content.
 * @details
 *  The JSON payload belonged to the 1.x C ABI, which stage 5 removed (design
 *  8.5). The reader stays for the tests only, where a payload is a short way
 *  to write down a NotificationContent; nothing in the library reads JSON from
 *  a caller any more.
 *
 *  It keeps the old parser's branching on whether a key is present rather
 *  than on whether its value is empty (input inventory 1.10), so a payload
 *  still describes absent and present-but-empty fields apart. Keys it does not
 *  know are ignored. Type errors are left to throw.
 */
#pragma once

#include <winrt/Windows.Data.Json.h>

#include "NativeToolkit/Notification.h"

namespace NotificationPayloadJson {

/**
 * @brief Reads a payload object.
 * @param json    The parsed payload.
 * @param content Filled in; untouched keys are left as the default.
 * @throws winrt::hresult_error when a value is not of the type its key needs,
 *         which is what the C ABI has always turned into HRESULT_FAILURE.
 */
void Read(const winrt::Windows::Data::Json::JsonObject& json,
          NativeToolkit::Notification::NotificationContent& content);

}  // namespace NotificationPayloadJson
