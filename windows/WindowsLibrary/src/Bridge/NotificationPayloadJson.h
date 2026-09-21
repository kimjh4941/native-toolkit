/**
 * @file NotificationPayloadJson.h
 * @brief Reads the C ABI's notification payload into the C++ API's content.
 * @details
 *  The JSON payload belongs to the C ABI, so its parser belongs here rather
 *  than in the library: a C++ caller hands over a NotificationContent and
 *  never sees a string of JSON.
 *
 *  What this has to reproduce is not "the keys" but "the branching". The old
 *  parser decided field by field on whether a key was present, which is not
 *  the same as whether its value is empty; section 1.10 of the input inventory
 *  lists the ten places the two differ, and NotificationPayloadTest pins each.
 *  That is why the fields it fills are optional.
 *
 *  Type errors are left to throw. A number where a string belongs has always
 *  come back as HRESULT_FAILURE from the WinRT exception, and the caller is
 *  where that is caught, exactly as before.
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
