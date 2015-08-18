#pragma once

#include "simply_msg.h"

#include "simply.h"

#include "util/color.h"
#include "util/status_bar_layer.h"

#include <pebble.h>

typedef struct SimplyWindow SimplyWindow;

struct SimplyWindow {
  Simply *simply;
  Window *window;
  StatusBarLayer *status_bar_layer;
  ScrollLayer *scroll_layer;
  Layer *layer;
  ActionBarLayer *action_bar_layer;
  const WindowHandlers *window_handlers;
  uint32_t id;
  ButtonId button_mask:4;
  GColor8 background_color;
  bool is_fullscreen:1;
  bool is_scrollable:1;
  bool is_action_bar:1;
  bool is_status_bar:1;
};

SimplyWindow *simply_window_init(SimplyWindow *self, Simply *simply);
void simply_window_deinit(SimplyWindow *self);
void simply_window_show(SimplyWindow *self);
void simply_window_hide(SimplyWindow *self);

void simply_window_preload(SimplyWindow *self);
void simply_window_load(SimplyWindow *self);
void simply_window_unload(SimplyWindow *self);
bool simply_window_appear(SimplyWindow *self);
bool simply_window_disappear(SimplyWindow *self);

void simply_window_single_click_handler(ClickRecognizerRef recognizer, void *context);

void simply_window_set_scrollable(SimplyWindow *self, bool is_scrollable);
void simply_window_set_fullscreen(SimplyWindow *self, bool is_fullscreen);
void simply_window_set_background_color(SimplyWindow *self, GColor8 background_color);

void simply_window_set_button(SimplyWindow *self, ButtonId button, bool enable);

void simply_window_set_action_bar(SimplyWindow *self, bool is_action_bar);
void simply_window_set_action_bar_icon(SimplyWindow *self, ButtonId button, uint32_t id);
void simply_window_set_action_bar_background_color(SimplyWindow *self, GColor8 background_color);
void simply_window_action_bar_clear(SimplyWindow *self);

bool simply_window_handle_packet(Simply *simply, Packet *packet);
