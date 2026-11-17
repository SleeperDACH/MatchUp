import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matchup/core/util/club_colors.dart';

void main() {
  const grau = ClubColors(Color(0xFF808080), Color(0xFF808080));

  test(
    'Länder in deutscher und englischer Schreibweise haben Trikotfarben',
    () {
      final de = clubColors('Deutschland', fallback: grau);
      expect(de.primary.computeLuminance(), greaterThan(0.8)); // weiß
      expect(clubColors('Germany', fallback: grau), same(de));

      final nl = clubColors('Niederlande', fallback: grau);
      expect(nl.primary, const Color(0xFFF36C21)); // orange
      expect(clubColors('Netherlands', fallback: grau).primary, nl.primary);

      expect(clubColors('Serbien', fallback: grau), isNot(same(grau)));
      expect(clubColors('Griechenland', fallback: grau), isNot(same(grau)));
      expect(clubColors('Türkei', fallback: grau), isNot(same(grau)));
      expect(clubColors('Österreich', fallback: grau), isNot(same(grau)));
    },
  );
}
