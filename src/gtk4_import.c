#include "gtk4_import.h"

gulong g_signal_connect_d(void* widget, const char* signal_name, void* callback, gpointer user_data)
{
	return g_signal_connect(widget, signal_name, G_CALLBACK(callback), user_data);
}

gulong g_signal_connect_swapped_d(void* widget, const char* signal_name, void* callback, gpointer user_data)
{
	return g_signal_connect_swapped(widget, signal_name, G_CALLBACK(callback), user_data);
}

gulong g_signal_connect_after_d(void* widget, const char* signal_name, void* callback, gpointer user_data)
{
	return g_signal_connect_after(widget, signal_name, G_CALLBACK(callback), user_data);
}

int get_window_position_and_size(GtkWindow *window, int *x, int *y, int *w, int *h) 
{
	// Get the GdkSurface for the GtkWindow
	GdkSurface *surface = gtk_native_get_surface(GTK_NATIVE(window));

	if (GDK_IS_X11_SURFACE(surface)) {
		// Obtain the X11 Display and Window ID
		Display *display = GDK_DISPLAY_XDISPLAY(gdk_surface_get_display(surface));
		//Window xid = GDK_X11_SURFACE_GET_XID(surface);
		Window xid = gdk_x11_surface_get_xid(surface);
		// X11 attributes structure to store window information
		XWindowAttributes attrs;
		XGetWindowAttributes(display, xid, &attrs);
		*w = attrs.width;
		*h = attrs.height;

        // Variables to hold the absolute position
        Window root_window;
        unsigned int border_width, depth;

        // Use XTranslateCoordinates to get the absolute position
        XTranslateCoordinates(display, xid, DefaultRootWindow(display),
                              0, 0, x, y, &root_window);
		return 1;
	} 
	return 0;
}

int set_window_position(GtkWindow *window, int x, int y) 
{
	// Get the GdkSurface for the GtkWindow
	GdkSurface *surface = gtk_native_get_surface(GTK_NATIVE(window));

	if (GDK_IS_X11_SURFACE(surface)) {
		// Obtain the X11 Display and Window ID
		Display *display = GDK_DISPLAY_XDISPLAY(gdk_surface_get_display(surface));
		Window xid = gdk_x11_surface_get_xid(surface);

		// printf (" move to %d %d", x, y);
		// Use XMoveWindow to set the window position
		XMoveWindow(display, xid, x, y);
		XFlush(display); // Ensure the move request is sent immediately

        XRaiseWindow(display, xid);

        // Optional: Add a small delay to allow for the move to take effect
        g_usleep(100000); // 100 milliseconds
		return 1;
	} 
	printf("is no x11 surface??");
	return 0;
}
