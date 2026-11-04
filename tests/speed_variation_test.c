#include <assert.h>
#include <math.h>
#include "../Shared/SpeedVariation.h"

int main(void) {
  assert(fabs(gps_speed_variation_target(40, 0, 20) - 32) < 1e-9);
  assert(fabs(gps_speed_variation_target(40, 1, 20) - 48) < 1e-9);
  assert(gps_speed_variation_percent(1) == 10);
  assert(gps_speed_variation_percent(101) == 100);
  assert(fabs(gps_speed_variation_target(40, 0.5, 5) - 40) < 1e-9);
  assert(fabs(gps_speed_variation_target(40, -1, 20) - 32) < 1e-9);
  assert(gps_speed_variation_target(0, 0, 100) == 1);
  return 0;
}
