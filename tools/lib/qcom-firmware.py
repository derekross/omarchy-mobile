# SPDX-License-Identifier: MIT
# Helpers for tools/extract-vendor-firmware on Qualcomm Pixels (sargo), with
# the Python standard library only. Run with python3 -I.
#
#   qcom-firmware.py radio-list RADIO.img
#       the files in the modem partition's image/ directory, one per line
#   qcom-firmware.py radio-get RADIO.img NAME OUT
#       copy image/NAME out of it
#   qcom-firmware.py board2 BDF BOARD_NAME OUT
#       an ath10k board-2.bin holding one entry, BDF under BOARD_NAME
#
# RADIO.img is a factory image's radio-<device>-*.img: an FBPK container
# (version 1) whose "modem" entry is the modem partition, a FAT12/16 file
# system. Nothing is mounted; the FAT is read as data. Only short (8.3)
# names are read, lower-cased, which is how the modem partition names its
# files (MBA.MBN is mba.mbn).
import struct
import sys

FBPK_HEADER = 0x54   # magic, version, 68-byte pack version, count, size
FBPK_ENTRY = 0x38    # type, 36-byte name, u64 size, next, crc


def die(msg):
    print(f"qcom-firmware: {msg}", file=sys.stderr)
    sys.exit(1)


def fbpk_entry(blob, want):
    if blob[:4] != b"FBPK":
        die("not an FBPK radio image")
    version, = struct.unpack_from("<I", blob, 4)
    if version != 1:
        die(f"FBPK version {version}, only 1 is known")
    count, = struct.unpack_from("<I", blob, 0x4C)
    off = FBPK_HEADER
    for _ in range(count):
        if off + FBPK_ENTRY > len(blob):
            die("FBPK entry table runs past the end")
        name = blob[off + 4:off + 40].split(b"\0", 1)[0].decode("ascii", "replace")
        size, = struct.unpack_from("<Q", blob, off + 40)
        data = off + FBPK_ENTRY
        if data + size > len(blob):
            die(f"FBPK entry {name} runs past the end")
        if name == want:
            return blob[data:data + size]
        off = data + size
        off += -off % 4
    die(f"no {want} entry in the radio image")


class Fat:
    def __init__(self, img):
        if len(img) < 512 or img[510:512] != b"\x55\xaa":
            die("the modem entry is not a FAT file system")
        (self.bps, self.spc, reserved, nfats, rootents, total16, _media,
         fatsz, _spt, _heads, _hidden, total32) = struct.unpack_from("<HBHBHHBHHHII", img, 11)
        if self.bps not in (512, 1024, 2048, 4096) or self.spc == 0 or fatsz == 0:
            die("the modem entry is not a FAT12/16 file system")
        self.img = img
        self.fat = reserved * self.bps
        self.root = self.fat + nfats * fatsz * self.bps
        self.rootents = rootents
        self.data = self.root + ((rootents * 32 + self.bps - 1) // self.bps) * self.bps
        total = total16 or total32
        clusters = (total - self.data // self.bps) // self.spc
        self.fat12 = clusters < 4085
        if clusters >= 65525:
            die("FAT32 is not expected on a modem partition")
        self.csize = self.bps * self.spc

    def next(self, c):
        if self.fat12:
            v, = struct.unpack_from("<H", self.img, self.fat + c * 3 // 2)
            v = v >> 4 if c & 1 else v & 0xFFF
            return None if v >= 0xFF8 else v
        v, = struct.unpack_from("<H", self.img, self.fat + c * 2)
        return None if v >= 0xFFF8 else v

    def chain(self, c, size=None):
        out, seen = bytearray(), set()
        while c is not None and c >= 2:
            if c in seen:
                die("a loop in the FAT")
            seen.add(c)
            at = self.data + (c - 2) * self.csize
            out += self.img[at:at + self.csize]
            c = self.next(c)
        return bytes(out if size is None else out[:size])

    def entries(self, raw):
        for i in range(0, len(raw) - 31, 32):
            e = raw[i:i + 32]
            if e[0] == 0:
                break
            if e[0] == 0xE5 or e[11] == 0x0F or e[11] & 0x08:
                continue   # deleted, a long-name part, the volume label
            base = e[0:8].decode("ascii", "replace").rstrip()
            ext = e[8:11].decode("ascii", "replace").rstrip()
            name = (base + ("." + ext if ext else "")).lower()
            cluster, size = struct.unpack_from("<HI", e, 26)
            yield name, bool(e[11] & 0x10), cluster, size

    def rootdir(self):
        return self.img[self.root:self.root + self.rootents * 32]

    def find(self, path):
        raw = self.rootdir()
        parts = path.strip("/").split("/")
        for i, part in enumerate(parts):
            for name, isdir, cluster, size in self.entries(raw):
                if name == part:
                    if i == len(parts) - 1:
                        return isdir, cluster, size
                    if not isdir:
                        die(f"{name} is not a directory")
                    raw = self.chain(cluster)
                    break
            else:
                die(f"no {path} in the modem partition")

    def listdir(self, path):
        isdir, cluster, _ = self.find(path)
        if not isdir:
            die(f"{path} is not a directory")
        return [n for n, d, _, _ in self.entries(self.chain(cluster)) if not d and n not in (".", "..")]

    def read(self, path):
        isdir, cluster, size = self.find(path)
        if isdir:
            die(f"{path} is a directory")
        data = self.chain(cluster, size)
        if len(data) != size:
            die(f"{path} is cut short in the FAT")
        return data


def board2(bdf, name, out):
    def pad(b):
        return b + b"\0" * (-len(b) % 4)

    def ie(i, data):
        return struct.pack("<II", i, len(data)) + pad(data)

    data = open(bdf, "rb").read()
    if not data:
        die(f"{bdf} is empty")
    # drivers/net/wireless/ath/ath10k/hw.h: the magic, then one BOARD IE
    # holding a NAME IE and a DATA IE
    blob = pad(b"QCA-ATH10K-BOARD\0") + ie(0, ie(0, name.encode()) + ie(1, data))
    with open(out, "wb") as f:
        f.write(blob)


def main(argv):
    if len(argv) == 2 and argv[0] == "radio-list":
        fat = Fat(fbpk_entry(open(argv[1], "rb").read(), "modem"))
        print("\n".join(sorted(fat.listdir("image"))))
    elif len(argv) == 4 and argv[0] == "radio-get":
        fat = Fat(fbpk_entry(open(argv[1], "rb").read(), "modem"))
        name = argv[2]
        if "/" in name or name.startswith("."):
            die(f"not a file name: {name}")
        with open(argv[3], "wb") as f:
            f.write(fat.read("image/" + name))
    elif len(argv) == 4 and argv[0] == "board2":
        board2(*argv[1:])
    else:
        die("usage: radio-list RADIO | radio-get RADIO NAME OUT | board2 BDF NAME OUT")


if __name__ == "__main__":
    main(sys.argv[1:])
