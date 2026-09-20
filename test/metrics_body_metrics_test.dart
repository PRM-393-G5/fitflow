import 'package:flutter_test/flutter_test.dart';
import 'package:prm/domain/body_metrics.dart';

void main() {
  test('BMI categories follow WHO cut-offs', () {
    expect(BodyMetrics.bmiCategory(17.9), 'Underweight');
    expect(BodyMetrics.bmiCategory(18.5), 'Normal');
    expect(BodyMetrics.bmiCategory(24.9), 'Normal');
    expect(BodyMetrics.bmiCategory(25), 'Overweight');
    expect(BodyMetrics.bmiCategory(30), 'Obese');
  });

  test('decimal parsing accepts a comma separator', () {
    expect(BodyMetrics.parseDecimal('70,5'), 70.5);
    expect(BodyMetrics.parseDecimal(' 70.5 '), 70.5);
    expect(BodyMetrics.parseDecimal('70kg'), isNull);
    expect(BodyMetrics.parseDecimal(''), isNull);
    expect(BodyMetrics.parseDecimal('NaN'), isNull);
  });

  test('validation enforces plausible ranges in the shown unit', () {
    expect(BodyMetrics.weightError('70,5', metric: true), isNull);
    expect(BodyMetrics.weightError('7', metric: true), isNotNull);
    expect(BodyMetrics.weightError('500', metric: true), isNotNull);
    // 500 lb ≈ 227 kg is fine; 30 lb ≈ 14 kg is not.
    expect(BodyMetrics.weightError('500', metric: false), isNull);
    expect(BodyMetrics.weightError('30', metric: false), contains('lb'));
    // The lb limits shown in the message are themselves accepted.
    final message = BodyMetrics.weightError('30', metric: false)!;
    expect(message, 'Enter a weight between 44 and 882 lb');
    expect(BodyMetrics.weightError('44', metric: false), isNull);
    expect(BodyMetrics.weightError('882', metric: false), isNull);
    expect(BodyMetrics.weightError('43.9', metric: false), message);
    expect(BodyMetrics.weightError('882.1', metric: false), message);
    expect(
      BodyMetrics.weightError('7', metric: true),
      'Enter a weight between 20 and 400 kg',
    );
    expect(BodyMetrics.weightError('400', metric: true), isNull);
    expect(BodyMetrics.heightError('175'), isNull);
    expect(BodyMetrics.heightError('5.9'), isNotNull);
    expect(BodyMetrics.ageError('12'), isNotNull);
    expect(BodyMetrics.ageError('30'), isNull);
    expect(BodyMetrics.feetInches(175), '5 ft 9 in');
  });
}
