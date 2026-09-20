/**
 * @file AppSdkRuntimeForTest.h
 * @brief Makes the Windows App Runtime available to the test process.
 * @details
 *  Anything that builds a real toast activates App SDK types, which an
 *  unpackaged process can only reach once the bootstrapper has made the
 *  runtime package available.
 *
 *  The bootstrap DLL is loaded by hand, from next to the test DLL, rather than
 *  linked. The rest of the tests deliberately avoid the App SDK, and linking it
 *  would make every one of them fail to load on a machine without the runtime;
 *  this way only the classes that ask for it are affected.
 *
 *  It is brought up once and never shut down. MddBootstrapShutdown while the
 *  process still holds activation factories from that runtime is not worth the
 *  risk for a test host that is about to exit anyway, and the order in which
 *  test classes run is not ours to choose.
 */
#pragma once

#include <string>

namespace AppSdkRuntimeForTest {

/// Empty when the runtime is available, otherwise why it is not.
const std::wstring& Ensure();

}  // namespace AppSdkRuntimeForTest
