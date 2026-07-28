/*
 * mousedrv.c
 *
 * Written by
 *  Randy Rossi <randy.rossi@gmail.com>
 *
 * This file is part of VICE, the Versatile Commodore Emulator.
 * See README for copyright notice.
 *
 *  This program is free software; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA
 *  02111-1307  USA.
 *
 */

#include "mousedrv.h"

#include <stdio.h>

/* Circle delivers USB mouse movement on core 0; VICE consumes it on core 1. */
static int mouse_pending_x;
static int mouse_pending_y;
static mouse_func_t mouse_funcs;

int mousedrv_resources_init(mouse_func_t *funcs) {
  mouse_funcs.mbl = funcs->mbl;
  mouse_funcs.mbr = funcs->mbr;
  mouse_funcs.mbm = funcs->mbm;
  mouse_funcs.mbu = funcs->mbu;
  mouse_funcs.mbd = funcs->mbd;

  return 0;
}

int mousedrv_cmdline_options_init(void) { return 0; }

void mousedrv_init(void) {}

void mousedrv_mouse_changed(void) {}

void mousedrv_poll(void) {
  int delta_x = __atomic_exchange_n(&mouse_pending_x, 0, __ATOMIC_ACQ_REL);
  int delta_y = __atomic_exchange_n(&mouse_pending_y, 0, __ATOMIC_ACQ_REL);

  if (delta_x != 0 || delta_y != 0) {
    mouse_move((float)delta_x, (float)delta_y);
  }
}

void emu_mouse_move(int x, int y) {
  __atomic_fetch_add(&mouse_pending_x, x, __ATOMIC_RELAXED);
  __atomic_fetch_add(&mouse_pending_y, y, __ATOMIC_RELAXED);
}

void emu_mouse_button_left(int pressed) {
  mouse_funcs.mbl(pressed);
}

void emu_mouse_button_right(int pressed) {
  mouse_funcs.mbr(pressed);
}

void emu_mouse_button_middle(int pressed) {
  mouse_funcs.mbm(pressed);
}

void emu_mouse_wheel_up(int pressed) {
  mouse_funcs.mbu(pressed);
}

void emu_mouse_wheel_down(int pressed) {
  mouse_funcs.mbd(pressed);
}
