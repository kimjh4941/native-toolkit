#include "pch.h"
#include "Dialog/Data/WindowsDialogFlags.h"
#include "Dialog/Domain/WindowsDialogMapping.h"

using namespace Microsoft::VisualStudio::CppUnitTestFramework;

// ============================================================================
// U-C of the stage 3 design, for the conversions between the public request
// types and the Win32 shapes.
//
// Two of these are places where a conversion could silently lose part of what
// it is given, which is the regression class the input inventory exists to
// prevent:
//
//  - the filter block, a string with embedded NULs that ends with two of them,
//    plus the "All Files" fallback (DLG-12);
//  - the packed multi-select buffer, whose count is of strings rather than of
//    files: N files arrive as N+1 entries led by their folder (DLG-02).
// ============================================================================

namespace WindowsDialogMappingTest
{

namespace Domain = NativeToolkit::Dialog::Domain;
namespace Data = NativeToolkit::Dialog::Data;
using namespace NativeToolkit::Dialog;

namespace
{
    // Turns the NUL-separated block into something an assertion can show.
    std::vector<std::wstring> SplitBlock(const std::wstring& block)
    {
        std::vector<std::wstring> parts;
        size_t start = 0;
        while (start < block.size() && block[start] != L'\0') {
            const size_t end = block.find(L'\0', start);
            parts.emplace_back(block, start, end - start);
            start = end + 1;
        }
        return parts;
    }
}

TEST_CLASS(DialogMappingTest)
{
public:

    // --- MessageBoxW flags --------------------------------------------------

    TEST_METHOD(Test_ToMessageBoxType_CombinesButtonsIconAndDefault)
    {
        AlertRequest request;
        request.buttons       = AlertButtons::YesNoCancel;
        request.icon          = AlertIcon::Warning;
        request.defaultButton = AlertDefaultButton::Second;

        const UINT type = Data::ToMessageBoxType(request);

        Assert::AreEqual<UINT>(MB_YESNOCANCEL | MB_ICONWARNING | MB_DEFBUTTON2, type);
    }

    TEST_METHOD(Test_ToMessageBoxType_DefaultRequestIsPlainOk)
    {
        Assert::AreEqual<UINT>(MB_OK | MB_DEFBUTTON1, Data::ToMessageBoxType(AlertRequest{}));
    }

    TEST_METHOD(Test_ToMessageBoxType_HelpAndTopMostAreFlags)
    {
        AlertRequest request;
        request.topMost        = true;
        request.showHelpButton = true;

        const UINT type = Data::ToMessageBoxType(request);

        Assert::AreEqual<UINT>(MB_TOPMOST, type & MB_TOPMOST);
        Assert::AreEqual<UINT>(MB_HELP, type & MB_HELP);
    }

    TEST_METHOD(Test_FromMessageBoxResult_CoversEveryButtonId)
    {
        Assert::IsTrue(AlertResult::Ok       == Data::FromMessageBoxResult(IDOK));
        Assert::IsTrue(AlertResult::Cancel   == Data::FromMessageBoxResult(IDCANCEL));
        Assert::IsTrue(AlertResult::Yes      == Data::FromMessageBoxResult(IDYES));
        Assert::IsTrue(AlertResult::No       == Data::FromMessageBoxResult(IDNO));
        Assert::IsTrue(AlertResult::Retry    == Data::FromMessageBoxResult(IDRETRY));
        Assert::IsTrue(AlertResult::Abort    == Data::FromMessageBoxResult(IDABORT));
        Assert::IsTrue(AlertResult::Ignore   == Data::FromMessageBoxResult(IDIGNORE));
        Assert::IsTrue(AlertResult::TryAgain == Data::FromMessageBoxResult(IDTRYAGAIN));
        Assert::IsTrue(AlertResult::Continue == Data::FromMessageBoxResult(IDCONTINUE));
        Assert::IsTrue(AlertResult::Close    == Data::FromMessageBoxResult(IDCLOSE));
        Assert::IsTrue(AlertResult::Help     == Data::FromMessageBoxResult(IDHELP));
    }

    // --- Filter block -------------------------------------------------------

    TEST_METHOD(Test_BuildFilterBlock_EmptyListGivesTheAllFilesFallback)
    {
        // What the C ABI uses when it is handed no filter at all (DLG-12).
        const std::wstring block = Domain::BuildFilterBlock({});
        const auto parts = SplitBlock(block);

        Assert::AreEqual<size_t>(2, parts.size());
        Assert::AreEqual(std::wstring(L"All Files"), parts[0]);
        Assert::AreEqual(std::wstring(L"*.*"), parts[1]);
    }

    TEST_METHOD(Test_BuildFilterBlock_JoinsPatternsWithSemicolons)
    {
        const std::wstring block = Domain::BuildFilterBlock({
            FileFilter{L"Text files", {L"*.txt", L"*.log"}},
            FileFilter{L"All files", {L"*.*"}},
        });
        const auto parts = SplitBlock(block);

        Assert::AreEqual<size_t>(4, parts.size());
        Assert::AreEqual(std::wstring(L"Text files"), parts[0]);
        Assert::AreEqual(std::wstring(L"*.txt;*.log"), parts[1]);
        Assert::AreEqual(std::wstring(L"All files"), parts[2]);
        Assert::AreEqual(std::wstring(L"*.*"), parts[3]);
    }

    TEST_METHOD(Test_BuildFilterBlock_EndsWithTwoNuls)
    {
        // Win32 reads the block until it sees the double NUL; without it the
        // dialog walks off the end of the string.
        const std::wstring block = Domain::BuildFilterBlock({FileFilter{L"Text", {L"*.txt"}}});

        Assert::IsTrue(block.size() >= 2);
        Assert::AreEqual(L'\0', block[block.size() - 1]);
        Assert::AreEqual(L'\0', block[block.size() - 2]);
    }

    TEST_METHOD(Test_BuildFilterBlock_EntryWithoutPatternsMatchesEverything)
    {
        const auto parts = SplitBlock(Domain::BuildFilterBlock({FileFilter{L"Anything", {}}}));

        Assert::AreEqual<size_t>(2, parts.size());
        Assert::AreEqual(std::wstring(L"*.*"), parts[1]);
    }

    // --- Packed multi-select buffers ---------------------------------------

    TEST_METHOD(Test_ExpandMultiFileBuffer_SingleSelectionIsAlreadyAFullPath)
    {
        // One file: the dialog writes the whole path and the count is 1.
        const wchar_t buffer[] = L"C:\\dir\\one.txt\0";

        const auto paths = Domain::ExpandMultiFileBuffer(buffer, 1);

        Assert::AreEqual<size_t>(1, paths.size());
        Assert::AreEqual(std::wstring(L"C:\\dir\\one.txt"), paths[0]);
    }

    TEST_METHOD(Test_ExpandMultiFileBuffer_ManySelectionsAreJoinedToTheFolder)
    {
        // Two files: folder first, then the names, so the count is 3 for 2
        // files. Reading that count as a file count is the mistake DLG-02
        // warns about.
        const wchar_t buffer[] = L"C:\\dir\0one.txt\0two.txt\0";

        const auto paths = Domain::ExpandMultiFileBuffer(buffer, 3);

        Assert::AreEqual<size_t>(2, paths.size());
        Assert::AreEqual(std::wstring(L"C:\\dir\\one.txt"), paths[0]);
        Assert::AreEqual(std::wstring(L"C:\\dir\\two.txt"), paths[1]);
    }

    TEST_METHOD(Test_ExpandMultiFileBuffer_FolderWithTrailingSeparatorIsNotDoubled)
    {
        const wchar_t buffer[] = L"C:\\\0one.txt\0";

        const auto paths = Domain::ExpandMultiFileBuffer(buffer, 2);

        Assert::AreEqual<size_t>(1, paths.size());
        Assert::AreEqual(std::wstring(L"C:\\one.txt"), paths[0]);
    }

    TEST_METHOD(Test_ExpandMultiFileBuffer_CancelGivesNothing)
    {
        const wchar_t buffer[] = L"\0";

        Assert::AreEqual<size_t>(0, Domain::ExpandMultiFileBuffer(buffer, 0).size());
        Assert::AreEqual<size_t>(0, Domain::ExpandMultiFileBuffer(nullptr, 1).size());
    }

    TEST_METHOD(Test_ExpandMultiFolderBuffer_EveryEntryIsAFullPath)
    {
        // The folder dialog packs full paths and its count is a folder count.
        const wchar_t buffer[] = L"C:\\one\0D:\\two\0";

        const auto paths = Domain::ExpandMultiFolderBuffer(buffer, 2);

        Assert::AreEqual<size_t>(2, paths.size());
        Assert::AreEqual(std::wstring(L"C:\\one"), paths[0]);
        Assert::AreEqual(std::wstring(L"D:\\two"), paths[1]);
    }
};

}  // namespace WindowsDialogMappingTest
