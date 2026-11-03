#ifndef GPSNAV_GEO_H
#define GPSNAV_GEO_H
typedef struct { double lat, lon; } GPSPoint;
double gps_distance(GPSPoint a, GPSPoint b);
double gps_bearing(GPSPoint a, GPSPoint b);
GPSPoint gps_interpolate(GPSPoint a, GPSPoint b, double t);
GPSPoint gps_offset(GPSPoint center, double meters, double bearing);
#endif
