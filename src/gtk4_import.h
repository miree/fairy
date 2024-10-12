#include "gdc_importc.h"

#include <gtk/gtk.h>
#include <gdk/gdk.h>

#include <gdk/x11/gdkx.h>
#include <X11/Xlib.h>

enum GdkButton {
	PRIMARY   = GDK_BUTTON_PRIMARY,
	MIDDLE    = GDK_BUTTON_MIDDLE,
	SECONDARY = GDK_BUTTON_SECONDARY,
};

gulong g_signal_connect_d(void* widget, const char* signal_name, void* callback, gpointer user_data);
// {
// 	g_signal_connect(widget, signal_name, G_CALLBACK(callback), user_data);
// }

gulong g_signal_connect_swapped_d(void* widget, const char* signal_name, void* callback, gpointer user_data);
// {
// 	g_signal_connect_swapped(widget, signal_name, G_CALLBACK(callback), user_data);
// }

gulong g_signal_connect_after_d(void* widget, const char* signal_name, void* callback, gpointer user_data);
// {
// 	g_signal_connect_after(widget, signal_name, G_CALLBACK(callback), user_data);
// }

int get_window_position_and_size(GtkWindow *window, int *x, int *y, int *w, int *h);
int set_window_position(GtkWindow *window, int x, int y);

