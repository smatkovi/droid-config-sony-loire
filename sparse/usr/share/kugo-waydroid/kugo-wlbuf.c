/*
 * kugo: preload for waydroid-runner (a QtWayland 5.6 compositor). libwayland-server's default
 * limit for the events queued to one client is 4 KiB; when Android's composer is briefly too
 * busy to read (opening an app on this phone), the queue fills, the client is dropped ("error
 * in client communication"), the composer aborts in hwc_wayland_thread and the session ends.
 * QtWayland 5.6 predates wl_display_set_default_max_buffer_size (libwayland >= 1.23), so set it
 * here, right after the display is created.
 *   build: gcc -shared -fPIC -O2 -o kugo-wlbuf.so kugo-wlbuf.c -ldl
 */
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stddef.h>
#include <stdio.h>

struct wl_display;

struct wl_display *wl_display_create(void)
{
	static struct wl_display *(*real)(void);
	void (*set_max)(struct wl_display *, size_t);
	struct wl_display *d;

	if (!real)
		real = (struct wl_display *(*)(void))dlsym(RTLD_NEXT, "wl_display_create");
	d = real ? real() : NULL;
	set_max = (void (*)(struct wl_display *, size_t))dlsym(RTLD_NEXT, "wl_display_set_default_max_buffer_size");
	if (d && set_max) {
		set_max(d, 1 << 20);
		fprintf(stderr, "kugo-wlbuf: client buffer limit raised to 1 MiB\n");
	}
	return d;
}
