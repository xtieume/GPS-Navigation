#include <assert.h>
#include <math.h>
#include "../Shared/Geo.h"
int main(void) {
  GPSPoint a = {0, 0}, b = {0, 0.001};
  assert(fabs(gps_distance(a,b)-111.195) < 0.5);
  assert(fabs(gps_bearing(a,b)-90) < 0.01);
  GPSPoint mid = gps_interpolate(a,b,0.5);
  assert(fabs(mid.lon-0.0005)<1e-9);
  GPSPoint p = gps_offset(a,100,0);
  assert(fabs(gps_distance(a,p)-100)<0.1);
  return 0;
}
