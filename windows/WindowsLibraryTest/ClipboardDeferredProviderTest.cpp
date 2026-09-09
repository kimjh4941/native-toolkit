#include "pch.h"
#include "../WindowsLibrary/WindowsClipboardDeferredProvider.h"

using namespace Microsoft::VisualStudio::CppUnitTestFramework;

namespace WindowsClipboardDeferredProviderTest
{

namespace
{
    struct ProviderContext
    {
        DWORD queriedSize = 4;
        DWORD actualSize = 4;
    };

    DWORD TestProvider(const wchar_t*, void* rawContext, BYTE* buffer,
                       DWORD bufferSize, DWORD* requiredSize)
    {
        auto* context = static_cast<ProviderContext*>(rawContext);
        if (!buffer)
        {
            *requiredSize = context->queriedSize;
            return CLIPBOARD_ERROR_BUFFER_TOO_SMALL;
        }
        if (bufferSize < context->actualSize)
        {
            *requiredSize = context->actualSize;
            return CLIPBOARD_ERROR_BUFFER_TOO_SMALL;
        }
        for (DWORD i = 0; i < context->actualSize; ++i) buffer[i] = static_cast<BYTE>(i + 1);
        *requiredSize = context->actualSize;
        return CLIPBOARD_ERROR_NONE;
    }
}

TEST_CLASS(ClipboardDeferredProviderTest)
{
public:
    TEST_METHOD(Test_Renderer_ActualSizeEqualsQuery_ReturnsExactGlobalMemory)
    {
        ProviderContext context{ 4, 4 };
        auto renderer = MakeDeferredRenderer(&TestProvider, &context, L"Custom");
        GlobalMem mem = renderer();
        Assert::IsTrue(mem.IsValid());
        Assert::AreEqual(static_cast<SIZE_T>(4), ::GlobalSize(mem.Get()));
    }

    TEST_METHOD(Test_Renderer_ActualSizeSmallerThanQuery_IsRejected)
    {
        ProviderContext context{ 4, 2 };
        auto renderer = MakeDeferredRenderer(&TestProvider, &context, L"Custom");
        Assert::IsFalse(renderer().IsValid());
    }

    TEST_METHOD(Test_Renderer_ActualSizeLargerThanQuery_IsRejected)
    {
        ProviderContext context{ 4, 8 };
        auto renderer = MakeDeferredRenderer(&TestProvider, &context, L"Custom");
        Assert::IsFalse(renderer().IsValid());
    }
};

} // namespace WindowsClipboardDeferredProviderTest
