#include "Geo.h"
#include <math.h>
#define R 6371000.0
#define RAD (M_PI / 180.0)
double gps_distance(GPSPoint a, GPSPoint b) {
 double dlat=(b.lat-a.lat)*RAD, dlon=(b.lon-a.lon)*RAD;
 double h=sin(dlat/2)*sin(dlat/2)+cos(a.lat*RAD)*cos(b.lat*RAD)*sin(dlon/2)*sin(dlon/2);
 return 2*R*asin(sqrt(fmin(1, fmax(0,h))));
}
double gps_bearing(GPSPoint a, GPSPoint b) {
 double d=(b.lon-a.lon)*RAD, y=sin(d)*cos(b.lat*RAD), x=cos(a.lat*RAD)*sin(b.lat*RAD)-sin(a.lat*RAD)*cos(b.lat*RAD)*cos(d);
 return fmod(atan2(y,x)/RAD+360,360);
}
GPSPoint gps_interpolate(GPSPoint a, GPSPoint b, double t) {
 double dl=fmod(b.lon-a.lon+540,360)-180;
 GPSPoint p={a.lat+(b.lat-a.lat)*t, fmod(a.lon+dl*t+540,360)-180}; return p;
}
GPSPoint gps_offset(GPSPoint c, double m, double bearing) {
 double d=m/R, br=bearing*RAD, lat=c.lat*RAD, lon=c.lon*RAD;
 double lat2=asin(sin(lat)*cos(d)+cos(lat)*sin(d)*cos(br));
 double lon2=lon+atan2(sin(br)*sin(d)*cos(lat),cos(d)-sin(lat)*sin(lat2));
 GPSPoint p={lat2/RAD, fmod(lon2/RAD+540,360)-180}; return p;
}
