#ifndef FLUTTER_MY_APPLICATION_H_
#define FLUTTER_MY_APPLICATION_H_

#include <gtk/gtk.h>

G_DECLARE_FINAL_TYPE(CodingBahasalication, my_application, MY, APPLICATION,
                     GtkApplication)

/**
 * my_application_new:
 *
 * Creates a new Flutter-based application.
 *
 * Returns: a new #CodingBahasalication.
 */
CodingBahasalication* my_application_new();

#endif  // FLUTTER_MY_APPLICATION_H_
