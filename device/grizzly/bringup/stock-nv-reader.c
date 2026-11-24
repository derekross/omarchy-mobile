// SPDX-License-Identifier: MIT
#define _GNU_SOURCE

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <inttypes.h>
#include <limits.h>
#include <linux/fs.h>
#include <linux/magic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/sysmacros.h>
#include <sys/vfs.h>
#include <sys/wait.h>
#include <unistd.h>

#define SNAPSHOT "/grizzly-inventory/nv-verified"
#define RUNTIME "/grizzly-inventory/usb2-runtime"
#define BLOCK_CLASS "/sys/class/block"
#define MOUNTINFO "/proc/self/mountinfo"
#define BUSYBOX "/grizzly-inventory/busybox"
#define TEMP_NODE ".nv-target"
#define SECTOR_SIZE 512
#define MAX_CHUNK (8U * 1024 * 1024)
#define MAX_ENTRIES 512
#define REQUEST_SIZE 128
#define PROBE_SIZE 1024

enum entry_kind { PARENT, TARGET, OTHER };

struct entry {
    enum entry_kind kind;
    char name[16];
    char path[512];
    unsigned major;
    unsigned minor;
    uint64_t sectors;
    const char *label;
};

static struct entry entries[MAX_ENTRIES];
static size_t entry_count;

static const struct {
    const char *label;
    uint64_t sectors;
    char parent;
} allowed[] = {
    { "persist", 262144, 'a' },
    { "nvdata", 409600, 'a' },
    { "nvram", 188416, 'a' },
    { "protect_f", 40960, 'a' },
    { "protect_s", 40960, 'a' },
    { "modemdp", 2048, 'a' },
    { "modem_a", 2840576, 'a' },
    { "modem_b", 2840576, 'a' },
    { "devinfo", 16, 'd' },
};

#define TARGET_COUNT (sizeof(allowed) / sizeof(allowed[0]))

static const struct entry *targets[TARGET_COUNT];
static const struct entry *parents[5];

static bool decimal(const char *value, uint64_t *result)
{
    uint64_t number = 0;

    if (!*value || (value[0] == '0' && value[1]))
        return false;
    for (; *value; value++) {
        if (*value < '0' || *value > '9' ||
            number > (UINT64_MAX - (*value - '0')) / 10)
            return false;
        number = number * 10 + (*value - '0');
    }
    *result = number;
    return true;
}

static int split(char *text, char **words, size_t capacity)
{
    size_t count = 0;

    while (*text) {
        if (*text == ' ' || count == capacity)
            return -1;
        words[count++] = text;
        text += strcspn(text, " ");
        if (*text) {
            *text++ = '\0';
            if (!*text)
                return -1;
        }
    }
    return (int)count;
}

static bool device_number(char *text, unsigned *major, unsigned *minor)
{
    char *colon = strchr(text, ':');
    uint64_t maj, min;

    if (!colon)
        return false;
    *colon = '\0';
    if (!decimal(text, &maj) || !decimal(colon + 1, &min) ||
        maj > 4095 || min > 1048575)
        return false;
    *major = (unsigned)maj;
    *minor = (unsigned)min;
    return true;
}

static int target_index(const char *label)
{
    for (size_t i = 0; i < TARGET_COUNT; i++)
        if (!strcmp(label, allowed[i].label))
            return (int)i;
    return -1;
}

static const struct entry *find_entry(const char *name)
{
    for (size_t i = 0; i < entry_count; i++)
        if (!strcmp(name, entries[i].name))
            return &entries[i];
    return NULL;
}

static bool snapshot_row(char *line)
{
    struct entry *entry = &entries[entry_count];
    char *word[6];
    size_t name_size;
    uint64_t partition;

    if (split(line, word, 6) != 6)
        return false;
    name_size = strlen(word[2]);
    if (name_size < 3 || name_size >= sizeof(entry->name) ||
        strncmp(word[2], "sd", 2) || word[2][2] < 'a' || word[2][2] > 'e' ||
        strlen(word[5]) >= sizeof(entry->path) ||
        strncmp(word[5], "/sys/devices/", 13) ||
        !strstr(word[5], "/3c2d0000.ufs/"))
        return false;
    if (!device_number(word[3], &entry->major, &entry->minor) || !entry->major ||
        !decimal(word[4], &entry->sectors) || find_entry(word[2]))
        return false;

    for (size_t i = 0; i < entry_count; i++)
        if (entries[i].major == entry->major && entries[i].minor == entry->minor)
            return false;

    strcpy(entry->name, word[2]);
    strcpy(entry->path, word[5]);
    if (!strcmp(word[0], "parent")) {
        unsigned parent = entry->name[2] - 'a';

        if (name_size != 3 || parents[parent] || strcmp(word[1], "-") ||
            entry->sectors)
            return false;
        entry->kind = PARENT;
        parents[parent] = entry;
    } else {
        if (!decimal(entry->name + 3, &partition) || !partition)
            return false;
        if (!strcmp(word[0], "target")) {
            int index = target_index(word[1]);

            if (index < 0 || targets[index] || entry->sectors != allowed[index].sectors ||
                entry->name[2] != allowed[index].parent)
                return false;
            entry->kind = TARGET;
            entry->label = allowed[index].label;
            targets[index] = entry;
        } else {
            if (strcmp(word[0], "other") || strcmp(word[1], "-") || entry->sectors)
                return false;
            entry->kind = OTHER;
        }
    }

    entry_count++;
    return true;
}

static bool snapshot_paths(void)
{
    for (size_t i = 0; i < entry_count; i++) {
        const struct entry *entry = &entries[i];
        char expected[sizeof(entry->path) + sizeof(entry->name)];
        const struct entry *parent = parents[entry->name[2] - 'a'];

        if (!parent)
            return false;
        if (entry->kind == PARENT) {
            char suffix[sizeof(entry->name) + sizeof("/block/")];
            size_t length = strlen(entry->path);

            snprintf(suffix, sizeof(suffix), "/block/%s", entry->name);
            if (length < strlen(suffix) ||
                strcmp(entry->path + length - strlen(suffix), suffix))
                return false;
        } else {
            snprintf(expected, sizeof(expected), "%s/%s", parent->path, entry->name);
            if (strcmp(expected, entry->path))
                return false;
        }
    }
    for (size_t i = 0; i < sizeof(parents) / sizeof(parents[0]); i++)
        if (!parents[i])
            return false;
    for (size_t i = 0; i < TARGET_COUNT; i++)
        if (!targets[i])
            return false;
    return true;
}

static bool trusted_ram_file(int fd, mode_t mode, bool directory)
{
    struct stat status;
    struct statfs filesystem;

    return !fstat(fd, &status) && !fstatfs(fd, &filesystem) &&
           (filesystem.f_type == TMPFS_MAGIC || filesystem.f_type == RAMFS_MAGIC) &&
           (directory ? S_ISDIR(status.st_mode) : S_ISREG(status.st_mode)) &&
           status.st_uid == 0 && (status.st_mode & 07777) == mode;
}

static bool load_snapshot(void)
{
    int fd = open(SNAPSHOT, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    FILE *snapshot;
    char line[768];
    bool valid = false;

    if (fd < 0)
        return false;
    if (!trusted_ram_file(fd, 0600, false) || !(snapshot = fdopen(fd, "r"))) {
        close(fd);
        return false;
    }

    while (fgets(line, sizeof(line), snapshot)) {
        size_t length = strlen(line);

        if (!length || line[length - 1] != '\n' || entry_count == MAX_ENTRIES)
            goto end;
        line[length - 1] = '\0';
        if (!snapshot_row(line))
            goto end;
    }
    valid = !ferror(snapshot) && snapshot_paths();
end:
    return !fclose(snapshot) && valid;
}

static FILE *open_sysfs(const struct entry *entry, const char *attribute)
{
    char path[sizeof(entry->path) + 32];
    int fd;
    FILE *file;

    snprintf(path, sizeof(path), "%s/%s", entry->path, attribute);
    fd = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0)
        return NULL;
    file = fdopen(fd, "r");
    if (!file)
        close(fd);
    return file;
}

static bool sysfs_value(const struct entry *entry, const char *attribute,
                        const char *expected)
{
    FILE *file = open_sysfs(entry, attribute);
    char line[64];
    size_t length;
    bool valid = false;

    if (!file)
        return false;
    if (fgets(line, sizeof(line), file)) {
        length = strlen(line);
        if (length && line[length - 1] == '\n') {
            line[length - 1] = '\0';
            valid = !strcmp(line, expected) && fgetc(file) == EOF && !ferror(file);
        }
    }
    return !fclose(file) && valid;
}

static bool no_holders(const struct entry *entry)
{
    char path[sizeof(entry->path) + 16];
    struct dirent *holder;
    bool empty = true;
    int fd;
    DIR *directory;

    snprintf(path, sizeof(path), "%s/holders", entry->path);
    fd = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (fd < 0)
        return false;
    directory = fdopendir(fd);
    if (!directory) {
        close(fd);
        return false;
    }
    errno = 0;
    while ((holder = readdir(directory)))
        if (strcmp(holder->d_name, ".") && strcmp(holder->d_name, "..")) {
            empty = false;
            break;
        }
    empty = empty && !errno;
    return !closedir(directory) && empty;
}

static bool uevent_matches(const struct entry *entry)
{
    FILE *file = open_sysfs(entry, "uevent");
    char line[768];
    char devname[32], major[16], minor[16], partname[32];
    const char *const expected[] = {
        devname, major, minor, entry->kind == PARENT ? "DEVTYPE=disk" : "DEVTYPE=partition",
        entry->kind == TARGET ? partname : NULL,
    };
    const char *const keys[] = { "DEVNAME=", "MAJOR=", "MINOR=", "DEVTYPE=", "PARTNAME=" };
    unsigned seen = 0;
    bool valid = true;

    if (!file)
        return false;
    snprintf(devname, sizeof(devname), "DEVNAME=%s", entry->name);
    snprintf(major, sizeof(major), "MAJOR=%u", entry->major);
    snprintf(minor, sizeof(minor), "MINOR=%u", entry->minor);
    if (entry->kind == TARGET)
        snprintf(partname, sizeof(partname), "PARTNAME=%s", entry->label);

    while (valid && fgets(line, sizeof(line), file)) {
        size_t length = strlen(line);

        if (!length || line[length - 1] != '\n') {
            valid = false;
            break;
        }
        line[length - 1] = '\0';
        for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); i++) {
            if (strncmp(line, keys[i], strlen(keys[i])))
                continue;
            valid = !(seen & (1U << i)) &&
                    (expected[i] ? !strcmp(line, expected[i]) :
                     entry->kind == OTHER && target_index(line + strlen(keys[i])) < 0);
            seen |= 1U << i;
            break;
        }
    }

    valid = valid && !ferror(file) && (seen & 15) == 15 &&
            (entry->kind != TARGET || seen & 16);
    return !fclose(file) && valid;
}

static bool entry_live(const struct entry *entry)
{
    char class_path[sizeof(BLOCK_CLASS) + sizeof(entry->name)];
    char actual_path[PATH_MAX];
    char expected[64];
    struct stat status;

    snprintf(class_path, sizeof(class_path), BLOCK_CLASS "/%s", entry->name);
    snprintf(expected, sizeof(expected), "%u:%u", entry->major, entry->minor);
    if (lstat(class_path, &status) || !S_ISLNK(status.st_mode) ||
        !realpath(class_path, actual_path) || strcmp(actual_path, entry->path) ||
        !sysfs_value(entry, "dev", expected) || !no_holders(entry))
        return false;
    if (entry->kind != OTHER && !sysfs_value(entry, "ro", "1"))
        return false;
    if (entry->kind == TARGET) {
        snprintf(expected, sizeof(expected), "%" PRIu64, entry->sectors);
        if (!sysfs_value(entry, "size", expected))
            return false;
    }
    return uevent_matches(entry);
}

static bool unmounted(void)
{
    FILE *mounts = fopen(MOUNTINFO, "re");
    char line[8192];
    bool valid = true;
    size_t count = 0;

    if (!mounts)
        return false;
    while (fgets(line, sizeof(line), mounts)) {
        char *field = strchr(line, ' ');
        unsigned maj, min;
        char *end;

        if (!field || !(field = strchr(field + 1, ' ')) ||
            !(end = strchr(++field, ' ')) || !strchr(end, '\n')) {
            valid = false;
            break;
        }
        *end = '\0';
        if (!device_number(field, &maj, &min)) {
            valid = false;
            break;
        }
        count++;
        for (size_t i = 0; i < entry_count; i++)
            if (entries[i].major == maj && entries[i].minor == min) {
                valid = false;
                break;
            }
        if (!valid)
            break;
    }
    valid = valid && !ferror(mounts) && count;
    return !fclose(mounts) && valid;
}

static bool inventory_live(void)
{
    DIR *class = opendir(BLOCK_CLASS);
    struct dirent *item;
    bool valid = true;

    if (!class)
        return false;
    errno = 0;
    while ((item = readdir(class)))
        if (!strncmp(item->d_name, "sd", 2) && !find_entry(item->d_name)) {
            valid = false;
            break;
        }
    valid = valid && !errno;
    if (closedir(class) || !valid)
        return false;
    for (size_t i = 0; i < entry_count; i++)
        if (!entry_live(&entries[i]))
            return false;
    return unmounted();
}

static bool block_fd_matches(int fd, const struct entry *entry)
{
    struct stat status;
    uint64_t bytes = 0;
    int ro = 0;

    return !fstat(fd, &status) && S_ISBLK(status.st_mode) &&
           status.st_rdev == makedev(entry->major, entry->minor) &&
           !ioctl(fd, BLKROGET, &ro) && ro == 1 &&
           !ioctl(fd, BLKGETSIZE64, &bytes) && bytes == entry->sectors * SECTOR_SIZE;
}

static int open_target(int runtime, const struct entry *entry)
{
    int fd;

    if (entry->kind != TARGET ||
        mknodat(runtime, TEMP_NODE, S_IFBLK | 0600, makedev(entry->major, entry->minor)))
        return -1;
    fd = openat(runtime, TEMP_NODE, O_RDONLY | O_NOFOLLOW | O_CLOEXEC | O_EXCL);
    if (unlinkat(runtime, TEMP_NODE, 0) || !block_fd_matches(fd, entry)) {
        if (fd >= 0)
            close(fd);
        return -1;
    }
    return fd;
}

static bool write_all(int fd, const void *buffer, size_t length)
{
    const char *next = buffer;

    while (length) {
        ssize_t count = write(fd, next, length);

        if (count < 0 && errno == EINTR)
            continue;
        if (count <= 0)
            return false;
        next += count;
        length -= (size_t)count;
    }
    return true;
}

static bool send_error(const char *code)
{
    char header[32];
    int length = snprintf(header, sizeof(header), "NV1 ERR %s\n", code);

    return length > 0 && (size_t)length < sizeof(header) &&
           write_all(STDOUT_FILENO, header, (size_t)length);
}

static bool send_reply(const void *buffer, size_t size)
{
    char header[32];
    int length = snprintf(header, sizeof(header), "NV1 OK %zu\n", size);

    return length > 0 && (size_t)length < sizeof(header) &&
           write_all(STDOUT_FILENO, header, (size_t)length) &&
           write_all(STDOUT_FILENO, buffer, size);
}

static int read_request(char request[REQUEST_SIZE])
{
    size_t used = 0;

    while (used < REQUEST_SIZE - 1) {
        unsigned char ch;
        ssize_t count = read(STDIN_FILENO, &ch, 1);

        if (count < 0 && errno == EINTR)
            continue;
        if (count <= 0)
            return -1;
        if (ch == '\n') {
            request[used] = '\0';
            return 0;
        }
        if (ch < 0x20 || ch > 0x7e)
            return -1;
        request[used++] = ch;
    }
    return -1;
}

static bool probe_reply(void)
{
    char body[PROBE_SIZE] = "compatible google,malibu-grizzly\n";
    size_t used = strlen(body);

    for (size_t i = 0; i < TARGET_COUNT; i++) {
        const struct entry *target = targets[i];
        int count = snprintf(body + used, sizeof(body) - used, "%s %s block 1 0 %" PRIu64 "\n",
                             target->label, target->name, target->sectors * SECTOR_SIZE);

        if (count <= 0 || (size_t)count >= sizeof(body) - used)
            return false;
        used += (size_t)count;
    }
    return send_reply(body, used);
}

static bool read_chunk(int fd, char *data, size_t remaining, uint64_t offset)
{
    while (remaining) {
        ssize_t count = pread(fd, data, remaining, (off_t)offset);

        if (count < 0 && errno == EINTR)
            continue;
        if (count <= 0)
            return false;
        remaining -= (size_t)count;
        data += count;
        offset += (uint64_t)count;
    }
    return true;
}

static bool hash_data(int fd, uint64_t bytes, char hash[65])
{
    char output[69];
    size_t used = 0;
    int stream[2], status;
    pid_t child, waited;
    ssize_t count = 0;

    if (pipe2(stream, O_CLOEXEC))
        return false;
    child = fork();
    if (child < 0) {
        close(stream[0]);
        close(stream[1]);
        return false;
    }
    if (!child) {
        if (dup2(fd, STDIN_FILENO) < 0 || dup2(stream[1], STDOUT_FILENO) < 0)
            _exit(1);
        close(STDERR_FILENO);
        execl(BUSYBOX, "busybox", "sha256sum", (char *)NULL);
        _exit(1);
    }
    close(stream[1]);
    while (used < sizeof(output)) {
        count = read(stream[0], output + used, sizeof(output) - used);
        if (count < 0 && errno == EINTR)
            continue;
        if (count <= 0)
            break;
        used += (size_t)count;
    }
    close(stream[0]);
    do {
        waited = waitpid(child, &status, 0);
    } while (waited < 0 && errno == EINTR);
    if (waited != child || !WIFEXITED(status) || WEXITSTATUS(status) || count != 0 ||
        used != 68 || memcmp(output + 64, "  -\n", 4) ||
        lseek(fd, 0, SEEK_CUR) != (off_t)bytes)
        return false;
    for (size_t i = 0; i < 64; i++)
        if (!strchr("0123456789abcdef", output[i]) || !output[i])
            return false;
    memcpy(hash, output, 64);
    hash[64] = '\n';
    return true;
}

static bool data_request(int runtime, const struct entry *entry,
                         bool hash, uint64_t offset, size_t length)
{
    char digest[65];
    char *payload = hash ? digest : malloc(length);
    bool handled;
    int fd;

    if (!payload)
        return send_error("IO");
    if (!inventory_live() || (fd = open_target(runtime, entry)) < 0) {
        send_error("GUARD");
        handled = false;
        goto done;
    }
    bool data_ok = hash ? hash_data(fd, entry->sectors * SECTOR_SIZE, digest) :
                          read_chunk(fd, payload, length, offset);
    bool guarded = block_fd_matches(fd, entry) && inventory_live();

    if (close(fd))
        guarded = false;
    if (!guarded) {
        send_error("GUARD");
        handled = false;
    } else if (!data_ok) {
        handled = send_error("IO");
    } else {
        handled = send_reply(payload, hash ? sizeof(digest) : length);
    }
done:
    if (!hash)
        free(payload);
    return handled;
}

static bool serial_loop(int runtime)
{
    char request[REQUEST_SIZE];
    char *word[5];

    while (!read_request(request)) {
        int count = split(request, word, sizeof(word) / sizeof(word[0]));
        bool hash;
        int index;
        uint64_t offset = 0, length = 0, bytes;

        if (count < 2 || strcmp(word[0], "NV1")) {
            if (!send_error("REQUEST"))
                break;
            continue;
        }
        if (count == 2 && !strcmp(word[1], "DONE"))
            return send_reply(NULL, 0);
        if (count == 2 && !strcmp(word[1], "PROBE")) {
            if (!inventory_live()) {
                send_error("GUARD");
                break;
            }
            if (!probe_reply())
                break;
            continue;
        }
        hash = count == 3 && !strcmp(word[1], "SHA256");
        if (!hash && (count != 5 || strcmp(word[1], "READ"))) {
            if (!send_error("REQUEST"))
                break;
            continue;
        }
        index = target_index(word[2]);
        if (index < 0) {
            if (!send_error("LABEL"))
                break;
            continue;
        }
        bytes = targets[index]->sectors * SECTOR_SIZE;
        if (!hash &&
            (!decimal(word[3], &offset) || !decimal(word[4], &length) ||
             offset % SECTOR_SIZE || length % SECTOR_SIZE || !length ||
             length > MAX_CHUNK || offset >= bytes || length > bytes - offset)) {
            if (!send_error("RANGE"))
                break;
            continue;
        }
        if (!data_request(runtime, targets[index], hash, offset, (size_t)length))
            break;
    }
    return false;
}

int main(int argc, char **argv)
{
    int runtime;
    bool finished;

    (void)argv;
    if (argc != 1 || !isatty(STDIN_FILENO) || !isatty(STDOUT_FILENO) ||
        !load_snapshot())
        return 1;
    runtime = open(RUNTIME, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC);
    if (runtime < 0)
        return 1;
    finished = trusted_ram_file(runtime, 0700, true) &&
               inventory_live() && serial_loop(runtime);
    if (close(runtime))
        return 1;
    return finished ? 0 : 1;
}
