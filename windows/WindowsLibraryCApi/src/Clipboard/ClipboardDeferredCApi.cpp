// Deferred rendering in the C ABI (OP-40, OP-41). Stage 5 design 7.5.3.
//
// The provider is wrapped once per reservation, and every copy the C++ API
// makes of it (one per format) shares one release guard. The reservation ends
// in the C++ API when it drops those copies - a new reservation, a write or
// clear, another program emptying the clipboard, recovery - and the guard's
// last share going is the release. A reservation that fails has only the
// share held here, so it is released as this call returns. Close and free end
// the reservation without the C++ API dropping anything, so the session calls
// the release itself there (ntk_clipboard_session_close, _free).

#include "NativeToolkitC/Clipboard.h"

#include <algorithm>
#include <memory>
#include <mutex>
#include <string>
#include <utility>
#include <vector>

#include "Clipboard/ClipboardConvert.h"
#include "Clipboard/ClipboardResult.h"
#include "Common/ReleaseGuard.h"

using namespace NativeToolkitC::Detail;
using namespace NativeToolkitC::Detail::Clipboard;

extern "C" ntk_clipboard_error NTK_CALL ntk_clipboard_reserve_deferred(
    ntk_clipboard_session* session, const char* const* formats, size_t count,
    ntk_clipboard_render_fn provider, void* user_data, ntk_release_fn release)
{
    return Run([&]() -> ntk_clipboard_error {
        // Taken before anything can fail, so every path below lets go of it.
        const auto guard = NewReleaseGuard(release, user_data);
        if (!session) return Fail(kInvalid);

        std::vector<std::wstring> names;
        if (!provider || count == 0 || !ToStrings(formats, count, names)) return Fail(kInvalid);

        {
            std::lock_guard<std::mutex> lock(session->guardsMutex);
            auto& guards = session->guards;
            guards.erase(std::remove_if(guards.begin(), guards.end(), [](const auto& weak) { return weak.expired(); }),
                         guards.end());
            guards.push_back(guard);
        }
        return Done(session->session.ReserveDeferred(names, MakeRenderProvider(provider, guard, session->gate)));
    });
}

extern "C" ntk_clipboard_error NTK_CALL ntk_clipboard_recover_deferred_state(ntk_clipboard_session* session)
{
    return WithSession(session, [](Api::Session& s) { return Done(s.RecoverDeferredState()); });
}

extern "C" ntk_clipboard_error NTK_CALL ntk_clipboard_render_target_set(
    ntk_clipboard_render_target* target, const uint8_t* data, size_t size)
{
    return Run([&]() -> ntk_clipboard_error {
        if (!target || target->set) return Fail(kInvalid);
        std::vector<std::byte> bytes;
        if (!ToBytes(data, size, bytes)) return Fail(kInvalid);
        target->bytes = std::move(bytes);
        target->set = true;
        return Succeed();
    });
}
