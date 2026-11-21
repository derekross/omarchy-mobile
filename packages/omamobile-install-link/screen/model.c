/* SPDX-License-Identifier: MIT */
/*
 * The daemon's screen lines (omamobile-linkd, daemon.rs `screen_line`) and
 * what the screen shows for them. Each line says what the first-start
 * screen should show now (the crate's `Screen`, INSTALL-LINK-PLAN §2.5):
 *
 *   code DIGITS     the code (six digits) to type in the installer
 *   wrong-code N    a wrong code; N tries before the code is replaced
 *   locked N        pairing locked for N s (a new code comes after);
 *                   0: until a volume key is pressed
 *   paired          a host is paired: the code is used up
 *   version         the installer speaks another protocol version
 *   setup           first-boot setup runs
 *   stopped STEP    first-boot setup stopped at STEP
 *   no-space        not enough space for the factory image
 *   damaged         the image arrived damaged and is sent again
 *   off             the session owns the display from now on: end
 *
 * Anything else is ignored. The daemon replays only its last line to a
 * screen that connects late, so a screen may learn of a state without the
 * code that goes with it: it then asks for a volume key, whose press makes
 * the daemon draw a new code and send it.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <string.h>
#include "screen.h"

void model_forget_code(struct model *m)
{
	explicit_bzero(m->code, sizeof(m->code));
}

void model_init(struct model *m)
{
	memset(m, 0, sizeof(*m));
	m->phase = PH_WAITING;
	m->pairing = P_NONE;
}

void model_disconnected(struct model *m)
{
	unsigned serial = m->code_serial;

	model_forget_code(m);
	model_init(m);
	m->code_serial = serial;
}

void model_connected(struct model *m)
{
	m->connected = 1;
}

/* A decimal number of at most `digits` digits, the whole of s */
static int number(const char *s, size_t len, int digits, unsigned *out)
{
	unsigned v = 0;

	if (len == 0 || len > (size_t)digits)
		return -1;
	for (size_t i = 0; i < len; i++) {
		if (s[i] < '0' || s[i] > '9')
			return -1;
		v = v * 10 + (unsigned)(s[i] - '0');
	}
	*out = v;
	return 0;
}

static int word_is(const char *line, size_t len, const char *w, const char **arg, size_t *alen)
{
	size_t wl = strlen(w);

	if (len < wl || memcmp(line, w, wl) != 0)
		return 0;
	if (len == wl) {
		*arg = line + len;
		*alen = 0;
		return 1;
	}
	if (line[wl] != ' ')
		return 0;
	*arg = line + wl + 1;
	*alen = len - wl - 1;
	return 1;
}

enum line_result model_line(struct model *m, const char *line, size_t len, double now)
{
	const char *a;
	size_t al;
	unsigned v;

	if (word_is(line, len, "code", &a, &al)) {
		if (al != CODE_LEN || number(a, al, CODE_LEN, &v) < 0)
			return L_IGNORED;
		model_forget_code(m);
		memcpy(m->code, a, CODE_LEN);
		m->code[CODE_LEN] = 0;
		m->code_serial++;
		m->pairing = P_CODE;
		m->note = N_NONE;
		return L_CHANGED;
	}
	if (word_is(line, len, "wrong-code", &a, &al)) {
		if (number(a, al, 3, &v) < 0)
			return L_IGNORED;
		m->note = N_WRONG;
		m->left = v;
		return L_CHANGED;
	}
	if (word_is(line, len, "locked", &a, &al)) {
		if (number(a, al, 6, &v) < 0)
			return L_IGNORED;
		/* The code shown is no longer of use: the daemon replaced it */
		model_forget_code(m);
		m->note = N_NONE;
		if (v == 0) {
			m->pairing = P_LOCKED_ACT;
		} else {
			m->pairing = P_LOCKED;
			m->lock_until = now + v;
		}
		return L_CHANGED;
	}
	if (len == 6 && memcmp(line, "paired", 6) == 0) {
		model_forget_code(m);
		m->pairing = P_PAIRED;
		m->note = N_NONE;
		return L_CHANGED;
	}
	if (len == 7 && memcmp(line, "version", 7) == 0) {
		m->note = N_VERSION;
		return L_CHANGED;
	}
	if (len == 5 && memcmp(line, "setup", 5) == 0) {
		m->phase = PH_SETUP;
		return L_CHANGED;
	}
	if (word_is(line, len, "stopped", &a, &al)) {
		/* A step's name: a word of the daemon's, shown as it is */
		if (al > STEP_MAX)
			al = STEP_MAX;
		for (size_t i = 0; i < al; i++) {
			char c = a[i];
			if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-' || c == '_' || c == '.'))
				return L_IGNORED;
		}
		memcpy(m->step, a, al);
		m->step[al] = 0;
		m->phase = PH_STOPPED;
		return L_CHANGED;
	}
	if (len == 8 && memcmp(line, "no-space", 8) == 0) {
		m->note = N_NOSPACE;
		return L_CHANGED;
	}
	if (len == 7 && memcmp(line, "damaged", 7) == 0) {
		m->note = N_DAMAGED;
		return L_CHANGED;
	}
	if (len == 3 && memcmp(line, "off", 3) == 0) {
		model_forget_code(m);
		m->off = 1;
		return L_CHANGED;
	}
	return L_IGNORED;
}

void model_texts(const struct model *m, double now, struct texts *t)
{
	memset(t, 0, sizeof(*t));
	if (!m->connected) {
		t->title = "Starting the install link";
		t->sub = "One moment.";
		t->sub_tone = T_MUTED;
		return;
	}
	switch (m->phase) {
	case PH_WAITING:
		t->title = "Waiting for the installer on your computer";
		break;
	case PH_SETUP:
		t->title = "Setting up the phone";
		break;
	case PH_STOPPED:
		snprintf(t->buf[0], sizeof(t->buf[0]), "Setup stopped at: %s", m->step[0] ? m->step : "a step");
		t->title = t->buf[0];
		t->title_tone = T_ERROR;
		break;
	}
	switch (m->pairing) {
	case P_CODE:
		t->code = m->code;
		t->sub = "Type this code in the installer.";
		t->hint = "Press a volume key for a new code.";
		break;
	case P_NONE:
		t->sub = "Press a volume key to show the code.";
		break;
	case P_LOCKED: {
		double left = m->lock_until - now;
		if (left > 0.5)
			snprintf(t->buf[1], sizeof(t->buf[1]),
				 "Too many wrong codes from the computer. A new code in %.0f s.", left);
		else
			snprintf(t->buf[1], sizeof(t->buf[1]),
				 "Too many wrong codes from the computer. A new code in a moment.");
		t->sub = t->buf[1];
		t->sub_tone = T_WARN;
		break;
	}
	case P_LOCKED_ACT:
		t->sub = "Too many wrong codes from the computer. Press a volume key for a new code.";
		t->sub_tone = T_WARN;
		break;
	case P_PAIRED:
		t->sub = "Connected to the installer. Carry on on your computer.";
		t->sub_tone = T_ACCENT;
		break;
	}
	switch (m->note) {
	case N_NONE:
		break;
	case N_WRONG:
		snprintf(t->buf[2], sizeof(t->buf[2]), "Wrong code from the computer: %u %s before a new code.",
			 m->left, m->left == 1 ? "more try" : "more tries");
		t->note = t->buf[2];
		t->note_tone = T_WARN;
		break;
	case N_VERSION:
		t->note = "The installer on your computer is too old or too new for this phone.";
		t->note_tone = T_ERROR;
		break;
	case N_NOSPACE:
		t->note = "Not enough space on the phone.";
		t->note_tone = T_ERROR;
		break;
	case N_DAMAGED:
		t->note = "The file from the computer was damaged. Sending again.";
		t->note_tone = T_WARN;
		break;
	}
}

static const char *phase_name[] = { "waiting", "setup", "stopped" };
static const char *pairing_name[] = { "none", "code", "locked", "locked-act", "paired" };
static const char *note_name[] = { "-", "wrong", "version", "no-space", "damaged" };

int model_trace(const struct model *m, char *out, size_t n)
{
	/* The code's serial and length, never its digits */
	return snprintf(out, n, "connected=%d phase=%s pairing=%s code=%s%u/%zu note=%s left=%u off=%d",
			m->connected, phase_name[m->phase], pairing_name[m->pairing], "#", m->code_serial,
			strlen(m->code), note_name[m->note], m->left, m->off);
}

void model_message(const struct model *m, double now, char *out, size_t n)
{
	struct texts t;

	model_texts(m, now, &t);
	if (t.code)
		snprintf(out, n, "%s. Code for the installer: %.3s %.3s", t.title, t.code, t.code + 3);
	else
		snprintf(out, n, "%s. %s%s%s", t.title, t.sub ? t.sub : "", t.note ? " " : "", t.note ? t.note : "");
}
