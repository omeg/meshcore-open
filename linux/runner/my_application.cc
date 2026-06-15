#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif
#include <glib/gstdio.h>

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr int kDefaultWindowWidth = 1280;
constexpr int kDefaultWindowHeight = 720;
constexpr int kMinimumWindowWidth = 640;
constexpr int kMinimumWindowHeight = 480;
constexpr char kWindowStateGroup[] = "window";

gchar* get_window_state_path() {
  g_autofree gchar* app_dir =
      g_build_filename(g_get_user_config_dir(), "meshcore_open", nullptr);
  g_mkdir_with_parents(app_dir, 0700);
  return g_build_filename(app_dir, "window-state.ini", nullptr);
}

gboolean window_rect_intersects_screen(GtkWindow* window,
                                       gint x,
                                       gint y,
                                       gint width,
                                       gint height) {
  GdkDisplay* display = gtk_widget_get_display(GTK_WIDGET(window));
  if (display == nullptr) {
    return TRUE;
  }

  const gint monitor_count = gdk_display_get_n_monitors(display);
  for (gint i = 0; i < monitor_count; ++i) {
    GdkMonitor* gdk_monitor = gdk_display_get_monitor(display, i);
    if (gdk_monitor == nullptr) {
      continue;
    }

    GdkRectangle monitor;
    gdk_monitor_get_geometry(gdk_monitor, &monitor);
    if (x < monitor.x + monitor.width && x + width > monitor.x &&
        y < monitor.y + monitor.height && y + height > monitor.y) {
      return TRUE;
    }
  }

  return FALSE;
}

gboolean key_file_has_int(GKeyFile* key_file, const gchar* key) {
  return g_key_file_has_key(key_file, kWindowStateGroup, key, nullptr);
}

void restore_window_state(GtkWindow* window) {
  g_autofree gchar* path = get_window_state_path();
  g_autoptr(GKeyFile) key_file = g_key_file_new();
  if (!g_key_file_load_from_file(key_file, path, G_KEY_FILE_NONE, nullptr)) {
    return;
  }

  gint width = kDefaultWindowWidth;
  gint height = kDefaultWindowHeight;
  if (key_file_has_int(key_file, "width") &&
      key_file_has_int(key_file, "height")) {
    width = g_key_file_get_integer(
        key_file, kWindowStateGroup, "width", nullptr);
    height = g_key_file_get_integer(
        key_file, kWindowStateGroup, "height", nullptr);
    if (width >= kMinimumWindowWidth && height >= kMinimumWindowHeight) {
      gtk_window_set_default_size(window, width, height);
    }
  }

  if (key_file_has_int(key_file, "x") && key_file_has_int(key_file, "y")) {
    const gint x =
        g_key_file_get_integer(key_file, kWindowStateGroup, "x", nullptr);
    const gint y =
        g_key_file_get_integer(key_file, kWindowStateGroup, "y", nullptr);
    if (window_rect_intersects_screen(window, x, y, width, height)) {
      gtk_window_move(window, x, y);
    }
  }

  if (g_key_file_has_key(
          key_file, kWindowStateGroup, "maximized", nullptr) &&
      g_key_file_get_boolean(
          key_file, kWindowStateGroup, "maximized", nullptr)) {
    gtk_window_maximize(window);
  }
}

void save_window_state(GtkWindow* window) {
  g_autofree gchar* path = get_window_state_path();
  g_autoptr(GKeyFile) key_file = g_key_file_new();
  g_key_file_load_from_file(key_file, path, G_KEY_FILE_NONE, nullptr);

  GdkWindow* gdk_window = gtk_widget_get_window(GTK_WIDGET(window));
  const gboolean maximized =
      gdk_window != nullptr &&
      (gdk_window_get_state(gdk_window) & GDK_WINDOW_STATE_MAXIMIZED) != 0;

  g_key_file_set_boolean(
      key_file, kWindowStateGroup, "maximized", maximized);

  if (!maximized) {
    gint x = 0;
    gint y = 0;
    gint width = 0;
    gint height = 0;
    gtk_window_get_position(window, &x, &y);
    gtk_window_get_size(window, &width, &height);

    if (width >= kMinimumWindowWidth && height >= kMinimumWindowHeight) {
      g_key_file_set_integer(key_file, kWindowStateGroup, "x", x);
      g_key_file_set_integer(key_file, kWindowStateGroup, "y", y);
      g_key_file_set_integer(key_file, kWindowStateGroup, "width", width);
      g_key_file_set_integer(key_file, kWindowStateGroup, "height", height);
    }
  }

  g_autofree gchar* data = g_key_file_to_data(key_file, nullptr, nullptr);
  g_file_set_contents(path, data, -1, nullptr);
}

gboolean save_window_state_cb(GtkWidget* widget,
                              GdkEvent*,
                              gpointer) {
  save_window_state(GTK_WINDOW(widget));
  return FALSE;
}

}  // namespace

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView *view)
{
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "meshcore_open");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "meshcore_open");
  }

  gtk_window_set_default_size(
      window, kDefaultWindowWidth, kDefaultWindowHeight);
  restore_window_state(window);
  g_signal_connect(window, "delete-event", G_CALLBACK(save_window_state_cb),
                   nullptr);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000 for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb), self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application, gchar*** arguments, int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
     g_warning("Failed to register: %s", error->message);
     *exit_status = 1;
     return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  //MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  //MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line = my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID,
                                     "flags", G_APPLICATION_NON_UNIQUE,
                                     nullptr));
}
