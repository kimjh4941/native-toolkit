// Uses libc++ in the consumer too, so the consumer and libntk.so each carry a libc++.
#include <string>
#include <NativeToolkitC/Spike.h>

extern "C" int consumer_cxx_check(void) {
    std::string s = std::to_string(ntk_spike_cxx_check());  // "6"
    s += "-consumer";
    return static_cast<int>(s.size());  // 10
}
