// SPDX-License-Identifier: MIT
// Refuse to run tests that write under $HOME unless HOME is a throwaway
// directory inside the temp dir and is not the user's real home. Runs from
// a static constructor, so it fires before main() and before any test.
#pragma once
#include <climits>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <pwd.h>
#include <string>
#include <unistd.h>

namespace home_guard {
inline std::string canonical(const char *path) {
    char buffer[PATH_MAX];
    return path && *path && realpath(path, buffer) ? std::string(buffer) : std::string();
}
[[noreturn]] inline void refuse(const char *why) {
    std::fprintf(stderr, "settings tests: refusing to run: %s.\n"
                         "Run them through packages/omamobile-settings/test/all (or the repo-wide tests/all), which sets HOME to a mktemp fixture.\n", why);
    std::fflush(stderr);
    _exit(2);
}
inline bool inside(const std::string &path, const std::string &dir) {
    return !dir.empty() && path.rfind(dir + "/", 0) == 0;
}
// Pure decision, testable without touching the real home. Returns nullptr when
// HOME is safe, otherwise the reason. A fixture strictly inside the real home is
// fine (CI's RUNNER_TEMP, mktemp -p build/) as long as it is inside the temp dir.
inline const char *home_verdict(const std::string &home, const std::string &real, const std::string &temp) {
    if (home.empty()) return "HOME is unset or does not exist";
    if (!real.empty() && (home == real || inside(real, home))) return "HOME is the real user home or contains it";
    if (!inside(home, temp)) return "HOME is not inside the temp directory";
    return nullptr;
}
inline const char *xdg_verdict(const std::string &path, const std::string &home, const std::string &real, const std::string &temp) {
    if (!real.empty() && (path == real || inside(real, path))) return "an XDG_*_HOME variable is the real user home or contains it";
    if (path != home && !inside(path, home) && !inside(path, temp))
        return "an XDG_*_HOME variable points outside the fixture HOME and temp directory";
    return nullptr;
}
inline void check() {
    const std::string home = canonical(std::getenv("HOME"));
    const passwd *entry = getpwuid(getuid());
    const std::string real = canonical(entry ? entry->pw_dir : nullptr);
    const char *tmpdir = std::getenv("TMPDIR");
    const std::string temp = canonical(tmpdir && *tmpdir ? tmpdir : "/tmp");
    if (const char *why = home_verdict(home, real, temp)) refuse(why);
    for (const char *name : {"XDG_STATE_HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_CACHE_HOME"}) {
        const char *value = std::getenv(name);
        if (!value || !*value) continue;
        // Resolved, so a ".." can't walk out of the fixture; one that does not
        // exist is refused (test/all makes all four before it runs anything).
        const std::string path = canonical(value);
        if (path.empty()) refuse("an XDG_*_HOME variable points to a directory that does not exist");
        if (const char *why = xdg_verdict(path, home, real, temp)) refuse(why);
    }
}
inline const bool checked = (check(), true);
}
