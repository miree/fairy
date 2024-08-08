#include "gdc_importc.h"

#include <gtk/gtk.h>
#include <gdk/gdk.h>

enum GdkButton {
	PRIMARY   = GDK_BUTTON_PRIMARY,
	MIDDLE    = GDK_BUTTON_MIDDLE,
	SECONDARY = GDK_BUTTON_SECONDARY,
};

void g_signal_connect_d(void* widget, const char* signal_name, void* callback, gpointer user_data)
{
	g_signal_connect(widget, signal_name, G_CALLBACK(callback), user_data);
}

void g_signal_connect_swapped_d(void* widget, const char* signal_name, void* callback, gpointer user_data)
{
	g_signal_connect_swapped(widget, signal_name, G_CALLBACK(callback), user_data);
}

void g_signal_connect_after_d(void* widget, const char* signal_name, void* callback, gpointer user_data)
{
	g_signal_connect_after(widget, signal_name, G_CALLBACK(callback), user_data);
}


