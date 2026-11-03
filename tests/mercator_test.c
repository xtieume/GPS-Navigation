#include <assert.h>
#include <math.h>
#include <stdio.h>
#include "../App/Mercator.h"
int main(void) {
  assert(fabs(gps_x(0) - 0.5) < 1e-12);
  assert(fabs(gps_y(0) - 0.5) < 1e-12);
  assert(fabs(gps_lon(gps_x(106.7009)) - 106.7009) < 1e-9);
  assert(fabs(gps_lat(gps_y(10.7769)) - 10.7769) < 1e-9);
  assert(isfinite(gps_y(90)));
  puts("Mercator math: PASS");
  return 0;
}
