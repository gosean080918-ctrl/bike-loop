/// Pure-Dart geohash encoder, no external dependencies.
/// Used for prefix-based geo queries and server-side aggregation. Precision 9 is about 4.8 m.
library;

const _base32 = '0123456789bcdefghjkmnpqrstuvwxyz';

String geohashEncode(double lat, double lng, {int precision = 9}) {
  var latMin = -90.0, latMax = 90.0;
  var lngMin = -180.0, lngMax = 180.0;
  var hash = StringBuffer();
  var even = true;
  var bit = 0, ch = 0;

  while (hash.length < precision) {
    if (even) {
      final mid = (lngMin + lngMax) / 2;
      if (lng >= mid) {
        ch = (ch << 1) + 1;
        lngMin = mid;
      } else {
        ch = ch << 1;
        lngMax = mid;
      }
    } else {
      final mid = (latMin + latMax) / 2;
      if (lat >= mid) {
        ch = (ch << 1) + 1;
        latMin = mid;
      } else {
        ch = ch << 1;
        latMax = mid;
      }
    }
    even = !even;
    if (++bit == 5) {
      hash.write(_base32[ch]);
      bit = 0;
      ch = 0;
    }
  }
  return hash.toString();
}
