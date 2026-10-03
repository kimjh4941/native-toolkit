// The clipboard history requests of the C ABI and the history handle
// (OP-42..OP-47). Stage 5 design 7.5.4.
//
// Each completion is wrapped so that it runs through the session's gate:
// once the handle is freed, a completion that is still to come reaches
// nobody (7.5.2). The C++ API decides everything else - that an accepted
// request completes exactly once, on the owner thread, never inside the call
// that started it - and the C ABI adds no count of its own.

#include "NativeToolkitC/Clipboard.h"

#include <memory>
#include <string>
#include <utility>

#include "Clipboard/ClipboardConvert.h"
#include "Clipboard/ClipboardResult.h"
#include "Common/Handles.h"

using namespace NativeToolkitC::Detail;
using namespace NativeToolkitC::Detail::Clipboard;

namespace {

/// The error and the raw value a completion passes on (E-18).
struct Outcome {
    ntk_clipboard_error error = NTK_CLIPBOARD_ERROR_NONE;
    uint32_t            systemCode = 0;
};

template <class T>
Outcome OutcomeOf(const Api::Result<T>& result) noexcept
{
    if (result.has_value()) return {};
    return {static_cast<ntk_clipboard_error>(result.error().code), result.error().systemCode};
}

/// Hands the accepted request's id back, when the caller asked for it.
ntk_clipboard_error Accepted(const Api::Result<Api::RequestId>& accepted, uint32_t* outRequestId) noexcept
{
    if (!accepted.has_value()) return Fail(accepted.error());
    if (outRequestId) *outRequestId = static_cast<uint32_t>(accepted.value());
    return Succeed();
}

Api::CompletionHandler StatusHandler(ntk_clipboard_completion_fn fn, void* userData,
                                     std::shared_ptr<CallbackGate> gate)
{
    return [fn, userData, gate = std::move(gate)](Api::RequestId id, Api::Result<void> result) {
        const auto outcome = OutcomeOf(result);
        gate->Run([&] {
            CallCaller([&] { fn(userData, static_cast<uint32_t>(id), outcome.error, outcome.systemCode); });
        });
    };
}

}  // namespace

// =============================================================================
// Requests (OP-42..OP-47)
// =============================================================================

extern "C" ntk_clipboard_error NTK_CALL ntk_clipboard_get_history(
    ntk_clipboard_session* session, ntk_clipboard_history_fn callback, void* user_data,
    uint32_t* out_request_id)
{
    return WithSession(session, [&](Api::Session& s) -> ntk_clipboard_error {
        if (!callback) return Fail(kInvalid);
        auto handler = [callback, user_data, gate = session->gate](Api::RequestId id,
                                                                   Api::Result<std::vector<Api::HistoryItem>> result) {
            const auto outcome = OutcomeOf(result);
            // Converting could fail for want of memory; the request still
            // completes, as a failure (the C++ API has already counted it).
            ntk_clipboard_history history;
            Outcome delivered = outcome;
            if (result.has_value()) {
                try {
                    history = ToHistory(result.value());
                } catch (...) {
                    delivered = {NTK_CLIPBOARD_ERROR_OUT_OF_MEMORY, static_cast<uint32_t>(NTK_CLIPBOARD_ERROR_OUT_OF_MEMORY)};
                }
            }
            const ntk_clipboard_history* lent = delivered.error == NTK_CLIPBOARD_ERROR_NONE ? &history : nullptr;
            gate->Run([&] {
                CallCaller([&] {
                    callback(user_data, static_cast<uint32_t>(id), delivered.error, delivered.systemCode, lent);
                });
            });
        };
        return Accepted(s.GetHistory(std::move(handler)), out_request_id);
    });
}

extern "C" ntk_clipboard_error NTK_CALL ntk_clipboard_restore_history_item(
    ntk_clipboard_session* session, const char* item_id, ntk_clipboard_completion_fn callback,
    void* user_data, uint32_t* out_request_id)
{
    return WithSession(session, [&](Api::Session& s) -> ntk_clipboard_error {
        std::wstring id;
        if (!callback || !RequiredText(item_id, id)) return Fail(kInvalid);
        return Accepted(s.RestoreHistoryItem(id, StatusHandler(callback, user_data, session->gate)), out_request_id);
    });
}

extern "C" ntk_clipboard_error NTK_CALL ntk_clipboard_delete_history_item(
    ntk_clipboard_session* session, const char* item_id, ntk_clipboard_completion_fn callback,
    void* user_data, uint32_t* out_request_id)
{
    return WithSession(session, [&](Api::Session& s) -> ntk_clipboard_error {
        std::wstring id;
        if (!callback || !RequiredText(item_id, id)) return Fail(kInvalid);
        return Accepted(s.DeleteHistoryItem(id, StatusHandler(callback, user_data, session->gate)), out_request_id);
    });
}

extern "C" ntk_clipboard_error NTK_CALL ntk_clipboard_clear_unpinned_history(
    ntk_clipboard_session* session, ntk_clipboard_completion_fn callback, void* user_data,
    uint32_t* out_request_id)
{
    return WithSession(session, [&](Api::Session& s) -> ntk_clipboard_error {
        if (!callback) return Fail(kInvalid);
        return Accepted(s.ClearUnpinnedHistory(StatusHandler(callback, user_data, session->gate)), out_request_id);
    });
}

extern "C" ntk_clipboard_error NTK_CALL ntk_clipboard_get_history_availability(
    ntk_clipboard_session* session, ntk_clipboard_availability_fn callback, void* user_data,
    uint32_t* out_request_id)
{
    return WithSession(session, [&](Api::Session& s) -> ntk_clipboard_error {
        if (!callback) return Fail(kInvalid);
        auto handler = [callback, user_data, gate = session->gate](Api::RequestId id,
                                                                   Api::Result<Api::HistoryAvailability> result) {
            const auto outcome = OutcomeOf(result);
            // Both flags mean nothing on failure, and are 0 then (7.5.4).
            const int32_t history = result.has_value() && result.value().historyEnabled ? 1 : 0;
            const int32_t roaming = result.has_value() && result.value().roamingEnabled ? 1 : 0;
            gate->Run([&] {
                CallCaller([&] {
                    callback(user_data, static_cast<uint32_t>(id), outcome.error, outcome.systemCode, history, roaming);
                });
            });
        };
        return Accepted(s.GetHistoryAvailability(std::move(handler)), out_request_id);
    });
}

extern "C" ntk_clipboard_error NTK_CALL ntk_clipboard_cancel_request(
    ntk_clipboard_session* session, uint32_t request_id)
{
    return WithSession(session, [&](Api::Session& s) { return Done(s.CancelRequest(static_cast<Api::RequestId>(request_id))); });
}

// =============================================================================
// The history handle (the argument of ntk_clipboard_history_fn)
// =============================================================================

namespace {

const ntk_clipboard_history::Item* ItemAt(const ntk_clipboard_history* history, size_t index) noexcept
{
    return history && index < history->items.size() ? &history->items[index] : nullptr;
}

const char* Nothing(size_t* outSize) noexcept
{
    if (outSize) *outSize = 0;
    return nullptr;
}

}  // namespace

extern "C" size_t NTK_CALL ntk_clipboard_history_count(const ntk_clipboard_history* history)
{
    return history ? history->items.size() : 0;
}

extern "C" const char* NTK_CALL ntk_clipboard_history_item_id(
    const ntk_clipboard_history* history, size_t index, size_t* out_size)
{
    const auto* item = ItemAt(history, index);
    return item ? Borrow(item->id, out_size) : Nothing(out_size);
}

extern "C" const char* NTK_CALL ntk_clipboard_history_item_text(
    const ntk_clipboard_history* history, size_t index, size_t* out_size)
{
    const auto* item = ItemAt(history, index);
    return item && item->hasText ? Borrow(item->text, out_size) : Nothing(out_size);
}

extern "C" size_t NTK_CALL ntk_clipboard_history_item_content_type_count(
    const ntk_clipboard_history* history, size_t index)
{
    const auto* item = ItemAt(history, index);
    return item ? item->contentTypes.size() : 0;
}

extern "C" const char* NTK_CALL ntk_clipboard_history_item_content_type_at(
    const ntk_clipboard_history* history, size_t index, size_t type_index, size_t* out_size)
{
    const auto* item = ItemAt(history, index);
    if (!item || type_index >= item->contentTypes.size()) return Nothing(out_size);
    return Borrow(item->contentTypes[type_index], out_size);
}

extern "C" int64_t NTK_CALL ntk_clipboard_history_item_timestamp_unix_ms(
    const ntk_clipboard_history* history, size_t index)
{
    const auto* item = ItemAt(history, index);
    return item ? item->unixMs : 0;
}
