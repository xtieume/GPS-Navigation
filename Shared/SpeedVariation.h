#ifndef GPSNAV_SPEED_VARIATION_H
#define GPSNAV_SPEED_VARIATION_H

#include <math.h>

static inline int gps_speed_variation_percent(int percent) {
  if (percent < 10) return 10;
  if (percent > 100) return 100;
  return percent;
}

static inline double gps_speed_variation_target(double baseKmh, double randomUnit, int percent) {
  int clampedPercent = gps_speed_variation_percent(percent);
  if (!isfinite(randomUnit)) randomUnit = 0.5;
  if (randomUnit < 0) randomUnit = 0;
  if (randomUnit > 1) randomUnit = 1;
  double speed = baseKmh * (1 + (randomUnit * 2 - 1) * clampedPercent / 100.0);
  return fmax(1, speed);
}

#endif
