/// Compares two `MAJOR.MINOR.PATCH` strings. Returns negative if [a] < [b],
/// 0 if equal, positive if [a] > [b]. Throws [FormatException] on bad input.
int compareSemver(String a, String b) {
  final pa = _parse(a);
  final pb = _parse(b);
  for (var i = 0; i < 3; i++) {
    final c = pa[i].compareTo(pb[i]);
    if (c != 0) return c;
  }
  return 0;
}

List<int> _parse(String s) {
  final parts = s.split('.');
  if (parts.length != 3) throw FormatException('Bad semver: $s');
  return parts.map((p) {
    final n = int.tryParse(p);
    if (n == null || n < 0) throw FormatException('Bad semver: $s');
    return n;
  }).toList(growable: false);
}
