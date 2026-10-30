/* SPDX-License-Identifier: MIT */
/* Load an uncompressed module with one finit_module call and no fallback. */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

int main(int argc, char **argv)
{
    struct stat info;
    int fd, result, saved_errno;

    if (argc < 2 || argc > 3) {
        fputs("Usage: module-load-once MODULE.ko [PARAMETERS]\n", stderr);
        return 2;
    }
    fd = open(argv[1], O_RDONLY | O_CLOEXEC | O_NONBLOCK);
    if (fd < 0) {
        perror("open module");
        return 1;
    }
    if (fstat(fd, &info) || !S_ISREG(info.st_mode) || info.st_size <= 0) {
        fputs("Module must be a nonempty regular file\n", stderr);
        close(fd);
        return 1;
    }
    result = syscall(SYS_finit_module, fd, argc == 3 ? argv[2] : "", 0);
    saved_errno = errno;
    close(fd);
    if (result) {
        errno = saved_errno;
        perror("finit_module (not retried)");
        return 1;
    }
    return 0;
}
