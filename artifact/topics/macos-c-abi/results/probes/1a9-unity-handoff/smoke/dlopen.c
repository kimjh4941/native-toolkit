// macOS C ABI 1a-9 probe: dlopen <dir>/NtkProbeMacCApi.framework from a program that links neither
// framework and has no rpath. The sibling NtkProbeMac.framework in <dir> must be found through the
// C ABI's own rpath @loader_path/../../.. (D-11, 1a-3; like Contents/PlugIns).
#include <dlfcn.h>
#include <mach-o/dyld.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

typedef struct ntk_string ntk_string;

int main(int argc, const char* argv[]) {
    if (argc != 2) { fprintf(stderr, "usage: dlopen <dir>\n"); return 2; }
    char path[4096];
    snprintf(path, sizeof path, "%s/NtkProbeMacCApi.framework/NtkProbeMacCApi", argv[1]);
    void* h = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!h) { printf("FAIL dlopen: %s\nDLOPEN FAIL\n", dlerror()); return 1; }
    uint32_t (*version)(void) = (uint32_t (*)(void))dlsym(h, "ntk_version");
    ntk_string* (*describe)(void) = (ntk_string* (*)(void))dlsym(h, "ntk_probe_describe");
    const char* (*data)(const ntk_string*) = (const char* (*)(const ntk_string*))dlsym(h, "ntk_string_data");
    void (*sfree)(ntk_string*) = (void (*)(ntk_string*))dlsym(h, "ntk_string_free");
    void* hidden = dlsym(h, "$s15NtkProbeMacCApi7RequestC");
    int ok = version && describe && data && sfree && version() == 0x020000;
    printf("%s dlsym ntk_version -> 0x%06x\n", ok ? "ok  " : "FAIL", version ? version() : 0);
    if (ok) {
        ntk_string* s = describe();
        const char* text = data(s);
        /* describe redacts paths, so find where dyld loaded NtkProbeMac from (not printed). */
        int core_beside = 0;
        for (uint32_t i = 0; i < _dyld_image_count(); i++) {
            const char* name = _dyld_get_image_name(i);
            if (strstr(name, "/NtkProbeMac.framework/") && strncmp(name, argv[1], strlen(argv[1])) == 0) core_beside = 1;
        }
        printf("%s NtkProbeMac loaded from the same folder; describe: %s\n", core_beside ? "ok  " : "FAIL", text);
        ok = core_beside;
        sfree(s);
    }
    printf("%s non-ntk symbol hidden (dlsym of a Swift symbol -> %p)\n", hidden == NULL ? "ok  " : "FAIL", hidden);
    ok = ok && hidden == NULL;
    printf("%s\n", ok ? "DLOPEN PASS" : "DLOPEN FAIL");
    return ok ? 0 : 1;
}
