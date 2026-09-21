#include "pch.h"
#include "Bridge/ClipboardPayloadJson.h"

#include <winrt/Windows.Data.Json.h>

#include <cstring>
#include <new>

#include "Clipboard/Domain/WindowsClipboardFormats.h"

using namespace winrt::Windows::Data::Json;
using namespace NativeToolkit::Clipboard;

namespace ClipboardPayloadJson {

bool ReadStringArray(const wchar_t* json, std::vector<std::wstring>& out)
{
    if (!json) return false;
    try {
        for (const auto& value : JsonArray::Parse(json)) {
            out.emplace_back(value.GetString());
        }
        return true;
    }
    catch (const std::bad_alloc&) { throw; }
    catch (...) { return false; }
}

bool ReadFormatItems(const wchar_t* json, std::vector<FormatPayload>& out)
{
    if (!json) return false;
    try {
        for (const auto& entry : JsonArray::Parse(json)) {
            const auto object = entry.GetObject();
            const std::wstring formatName{
                object.HasKey(L"format") ? object.GetNamedString(L"format") : L""};

            const bool hasText = object.HasKey(L"text");
            const bool hasHtml = object.HasKey(L"html");
            const bool hasBytes = object.HasKey(L"base64");
            if ((hasText ? 1 : 0) + (hasHtml ? 1 : 0) + (hasBytes ? 1 : 0) != 1) {
                return false;
            }

            if (hasText) {
                out.push_back(TextPayload{formatName, std::wstring{object.GetNamedString(L"text")}});
            } else if (hasHtml) {
                out.push_back(HtmlPayload{formatName, std::wstring{object.GetNamedString(L"html")}});
            } else {
                std::vector<BYTE> decoded;
                const std::wstring encoded{object.GetNamedString(L"base64")};
                if (!ClipboardFormats::Base64Decode(ClipboardFormats::WideToUtf8(encoded), decoded)) {
                    return false;
                }
                std::vector<std::byte> bytes(decoded.size());
                if (!decoded.empty()) ::memcpy(bytes.data(), decoded.data(), decoded.size());
                out.push_back(BytesPayload{formatName, std::move(bytes)});
            }
        }
        return true;
    }
    catch (const std::bad_alloc&) { throw; }
    catch (...) { return false; }
}

std::wstring WriteStringArray(const std::vector<std::wstring>& values)
{
    JsonArray array;
    for (const auto& value : values) {
        array.Append(JsonValue::CreateStringValue(value));
    }
    return std::wstring{array.Stringify()};
}

}  // namespace ClipboardPayloadJson
