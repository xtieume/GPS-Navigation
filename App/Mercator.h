#ifndef GPSNAV_MERCATOR_H
#define GPSNAV_MERCATOR_H
#include <math.h>
static inline double gps_x(double longitude) { return (longitude + 180.0) / 360.0; }
static inline double gps_y(double latitude) {
  latitude = fmax(-85.05112878, fmin(85.05112878, latitude));
  double radians = latitude * M_PI / 180.0;
  return (1.0 - asinh(tan(radians)) / M_PI) / 2.0;
}
static inline double gps_lon(double x) { return x * 360.0 - 180.0; }
static inline double gps_lat(double y) { return atan(sinh(M_PI * (1.0 - 2.0 * y))) * 180.0 / M_PI; }
#endif
