import '../models.dart';

class RapidDosePreview {
  const RapidDosePreview({
    required this.base,
    required this.sliding,
    required this.total,
    required this.lowGlucose,
    required this.highGlucose,
  });

  final double base;
  final double sliding;
  final double total;
  final bool lowGlucose;
  final bool highGlucose;
}

RapidDosePreview? computeRapidDosePreview({
  required String mealTag,
  required double glucoseMgDl,
  required InsulinProfileModel profile,
}) {
  if (!profile.isRapid) {
    return null;
  }

  final normalizedMeal = _normalizeMealTag(mealTag);
  final base = _resolveBaseUnits(normalizedMeal, profile);
  final sliding = computeSlidingScale(glucoseMgDl, profile.slidingScaleMgdl);
  final total = _roundToTwo(base + sliding);

  return RapidDosePreview(
    base: base,
    sliding: sliding,
    total: total,
    lowGlucose: glucoseMgDl < 70,
    highGlucose: glucoseMgDl >= 250,
  );
}

double computeSlidingScale(double glucoseMgDl, List<num> thresholds) {
  if (!glucoseMgDl.isFinite) {
    return 0;
  }

  final normalized = thresholds
      .map((value) => value.toDouble())
      .where((value) => value.isFinite && value >= 0)
      .toSet()
      .toList()
    ..sort();

  var units = 0.0;
  for (final threshold in normalized) {
    if (glucoseMgDl >= threshold) {
      units += 1;
    }
  }
  return units;
}

double _resolveBaseUnits(String mealTag, InsulinProfileModel profile) {
  final mealSpecific = profile.mealBaseUnits[mealTag];
  if (mealSpecific != null) {
    return _roundToTwo(mealSpecific.toDouble());
  }

  if (profile.defaultBaseUnits != null) {
    return _roundToTwo(profile.defaultBaseUnits!.toDouble());
  }

  return 0;
}

String _normalizeMealTag(String mealTag) {
  final value = mealTag.trim().toLowerCase();
  if (value == 'breakfast' || value == 'lunch' || value == 'dinner' || value == 'snack') {
    return value;
  }
  return 'none';
}

double _roundToTwo(double value) {
  return (value * 100).round() / 100;
}
