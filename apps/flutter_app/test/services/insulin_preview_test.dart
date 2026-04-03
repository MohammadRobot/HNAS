import 'package:flutter_app/src/models.dart';
import 'package:flutter_app/src/services/insulin_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('computeSlidingScale', () {
    test('counts normalized thresholds at or below glucose', () {
      expect(
        computeSlidingScale(250, [200, 150, 200, -10, double.nan, 250]),
        3,
      );
    });

    test('returns zero for non-finite glucose', () {
      expect(computeSlidingScale(double.nan, [150, 200]), 0);
      expect(computeSlidingScale(double.infinity, [150, 200]), 0);
    });
  });

  group('computeRapidDosePreview', () {
    final rapidProfile = InsulinProfileModel(
      id: 'rapid_profile',
      type: 'rapid',
      label: 'Humalog',
      slidingScaleMgdl: const [150, 200, 250],
      mealBaseUnits: const {
        'breakfast': 4,
        'lunch': 5,
      },
      defaultBaseUnits: 2,
    );

    test('returns null for non-rapid profiles', () {
      const basalProfile = InsulinProfileModel(
        id: 'basal_profile',
        type: 'basal',
        label: 'Tresiba',
        fixedUnits: 18,
      );

      final preview = computeRapidDosePreview(
        mealTag: 'breakfast',
        glucoseMgDl: 180,
        profile: basalProfile,
      );

      expect(preview, isNull);
    });

    test('computes base, sliding, total, and high glucose flag', () {
      final preview = computeRapidDosePreview(
        mealTag: 'Breakfast',
        glucoseMgDl: 260,
        profile: rapidProfile,
      );

      expect(preview, isNotNull);
      expect(preview!.base, 4);
      expect(preview.sliding, 3);
      expect(preview.total, 7);
      expect(preview.lowGlucose, isFalse);
      expect(preview.highGlucose, isTrue);
    });

    test('falls back to default base and low glucose flag', () {
      final preview = computeRapidDosePreview(
        mealTag: 'brunch',
        glucoseMgDl: 69,
        profile: rapidProfile,
      );

      expect(preview, isNotNull);
      expect(preview!.base, 2);
      expect(preview.sliding, 0);
      expect(preview.total, 2);
      expect(preview.lowGlucose, isTrue);
      expect(preview.highGlucose, isFalse);
    });

    test('rounds to two decimals for base and total', () {
      const decimalProfile = InsulinProfileModel(
        id: 'rapid_profile_decimal',
        type: 'rapid',
        label: 'Rapid',
        slidingScaleMgdl: [100],
        mealBaseUnits: {'snack': 1.235},
      );

      final preview = computeRapidDosePreview(
        mealTag: 'snack',
        glucoseMgDl: 180,
        profile: decimalProfile,
      );

      expect(preview, isNotNull);
      expect(preview!.base, 1.24);
      expect(preview.sliding, 1);
      expect(preview.total, 2.24);
    });
  });
}
