// SPDX-License-Identifier: MIT
// omamobile-tarnorm: a tar stream on stdin to stdout, with the one part that
// differs between two reads of the same tree taken out, so that its SHA-256
// can be compared (tools/phone-encrypt, docs/SECURITY-PLAN.md §11.6).
//
// GNU tar names a sparse file's ustar header "DIR/GNUSparseFile.PID/NAME"
// (the real name is in its pax header), and the PID is tar's own. Here every
// header block's name and prefix fields get "GNUSparseFile.0" in its place,
// NUL-padded, and the header checksum field is zeroed. Nothing else changes.
// tools/phone-encrypt's tarnorm() does exactly the same in Python.
//
// The stream is walked block by block: a header, then its size's worth of
// data blocks (rounded up to 512 bytes), then the next header. An all-zero
// block is the end marker or padding.
#include <stdint.h>
#include <string.h>
#include <unistd.h>

#define BLOCK 512

static int read_block(unsigned char *b)
{
	size_t got = 0;

	while (got < BLOCK) {
		ssize_t n = read(0, b + got, BLOCK - got);

		if (n <= 0)
			return got ? -1 : 0; /* a short last block is an error */
		got += n;
	}
	return 1;
}

static int write_all(const unsigned char *b, size_t len)
{
	while (len) {
		ssize_t n = write(1, b, len);

		if (n <= 0)
			return -1;
		b += n;
		len -= n;
	}
	return 0;
}

static uint64_t field_size(const unsigned char *f)
{
	uint64_t v = 0;

	if (f[0] & 0x80) { /* base-256, for 8 GiB and more */
		for (int i = 1; i < 12; i++)
			v = v << 8 | f[i];
		return v;
	}
	for (int i = 0; i < 12 && f[i]; i++)
		if (f[i] >= '0' && f[i] <= '7')
			v = v * 8 + (f[i] - '0');
	return v;
}

/* In field f of length len: "GNUSparseFile." digits -> "GNUSparseFile.0" */
static void normalize(unsigned char *f, size_t len)
{
	static const char key[] = "GNUSparseFile.";
	size_t k = sizeof(key) - 1;

	for (size_t i = 0; i + k <= len; i++) {
		size_t j = i + k, end = j;

		if (memcmp(f + i, key, k))
			continue;
		while (end < len && f[end] >= '0' && f[end] <= '9')
			end++;
		if (end == j)
			continue;
		f[j] = '0';
		memmove(f + j + 1, f + end, len - end);
		memset(f + len - (end - j - 1), 0, end - j - 1);
	}
}

int main(void)
{
	unsigned char b[BLOCK];
	uint64_t data = 0; /* data blocks still to pass through */
	int r;

	while ((r = read_block(b)) > 0) {
		if (data) {
			data--;
		} else {
			static const unsigned char zero[BLOCK];

			if (memcmp(b, zero, BLOCK)) {
				uint64_t size = field_size(b + 124);

				normalize(b, 100);       /* name */
				normalize(b + 345, 155); /* prefix */
				memset(b + 148, 0, 8);   /* chksum */
				data = (size + BLOCK - 1) / BLOCK;
			}
		}
		if (write_all(b, BLOCK))
			return 1;
	}
	return r < 0 || data ? 1 : 0;
}
