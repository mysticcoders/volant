// Asks the sandbox, without touching the file system, whether this process may read each path.
// Prints one line per path and exits 1 when an expectation fails or the process is not sandboxed.
// Usage: probe allow|deny <path> [allow|deny <path> ...]
#include <stdio.h>
#include <string.h>
#include <unistd.h>

int sandbox_check(pid_t pid, const char *operation, int type, ...);
enum { SANDBOX_FILTER_PATH = 1, SANDBOX_CHECK_NO_REPORT = 0x40000000 };

int main(int argc, char **argv) {
    if (sandbox_check(getpid(), NULL, 0) != 1) {
        fprintf(stderr, "FAIL: the probe is not sandboxed, so it cannot test the entitlements\n");
        return 1;
    }
    int failed = 0;
    for (int i = 1; i + 1 < argc; i += 2) {
        int allowed = sandbox_check(getpid(), "file-read-data", SANDBOX_FILTER_PATH | SANDBOX_CHECK_NO_REPORT, argv[i + 1]) == 0;
        int expected = strcmp(argv[i], "allow") == 0;
        printf("%s: %s read %s\n", allowed == expected ? "PASS" : "FAIL", allowed ? "may" : "may not", argv[i + 1]);
        failed |= allowed != expected;
    }
    return failed;
}
