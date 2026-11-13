/* SPDX-License-Identifier: MIT */
/*
 * The colours: the image's default Omarchy theme. No account exists yet,
 * so there is no chosen theme; Omarchy's installer sets "Tokyo Night"
 * (install/user/theme.sh), and the screen reads that theme's colors.toml
 * from the omarchy package. Its values are built in too, for an image
 * without the file.
 */
#include <stdio.h>
#include <string.h>
#include "screen.h"

#define DEFAULT_THEME "/usr/share/omarchy/themes/tokyo-night/colors.toml"

static int hex(const char *s, uint32_t *out)
{
	uint32_t v = 0;

	if (s[0] != '#')
		return -1;
	for (int i = 1; i <= 6; i++) {
		char c = s[i];
		v <<= 4;
		if (c >= '0' && c <= '9')
			v |= (uint32_t)(c - '0');
		else if (c >= 'a' && c <= 'f')
			v |= (uint32_t)(c - 'a' + 10);
		else if (c >= 'A' && c <= 'F')
			v |= (uint32_t)(c - 'A' + 10);
		else
			return -1;
	}
	*out = v;
	return 0;
}

void theme_load(struct theme *th, const char *file)
{
	/* Tokyo Night, as /usr/share/omarchy/themes/tokyo-night/colors.toml */
	th->background = 0x1a1b26;
	th->foreground = 0xa9b1d6;
	th->bright = 0xc0caf5;
	th->accent = 0x7aa2f7;
	th->muted = 0x565f89;
	th->warn = 0xe0af68;
	th->error = 0xf7768e;

	FILE *f = fopen(file ? file : DEFAULT_THEME, "re");
	if (!f)
		return;
	char line[256];
	while (fgets(line, sizeof(line), f)) {
		char key[64];
		char val[16];
		uint32_t c;
		if (sscanf(line, " %63[a-z_] = \"%15[^\"]\"", key, val) != 2 || strlen(val) != 7 || hex(val, &c) < 0)
			continue;
		if (!strcmp(key, "background"))
			th->background = c;
		else if (!strcmp(key, "foreground"))
			th->foreground = c;
		else if (!strcmp(key, "bright_foreground"))
			th->bright = c;
		else if (!strcmp(key, "accent"))
			th->accent = c;
		else if (!strcmp(key, "dark_foreground"))
			th->muted = c;
		else if (!strcmp(key, "yellow"))
			th->warn = c;
		else if (!strcmp(key, "red"))
			th->error = c;
	}
	fclose(f);
}
