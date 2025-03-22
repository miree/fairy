#include "gdc_importc.h"

#include <gtk/gtk.h>
#include <gdk/gdk.h>

#include <gdk/x11/gdkx.h>
#include <X11/Xlib.h>
#include <X11/Xatom.h>

enum GdkButton {
	PRIMARY   = GDK_BUTTON_PRIMARY,
	MIDDLE    = GDK_BUTTON_MIDDLE,
	SECONDARY = GDK_BUTTON_SECONDARY,
};

enum XaAtom {
	XA_ATOM_ = XA_ATOM,
};

enum PropMode {
	Replace = PropModeReplace,
	Prepend = PropModePrepend,
	Append = PropModeAppend,
};

gulong g_signal_connect_d(void* widget, const char* signal_name, void* callback, gpointer user_data);
gulong g_signal_connect_swapped_d(void* widget, const char* signal_name, void* callback, gpointer user_data);
gulong g_signal_connect_after_d(void* widget, const char* signal_name, void* callback, gpointer user_data);

int get_window_position_and_size(GtkWindow *window, int *x, int *y, int *w, int *h);
int set_window_position(GtkWindow *window, int x, int y);

