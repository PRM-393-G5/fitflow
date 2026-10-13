import 'package:flutter_test/flutter_test.dart';
import 'package:prm/domain/load_math.dart';

void main() {
  const lb = LoadMath.lbPerKg;

  test('steps up to the next load the gym has', () {
    expect(LoadMath.increase(4, 0.025, metric: true), 5);
    expect(LoadMath.increase(60, 0.025, metric: true), 62.5);
    expect(LoadMath.increase(100, 0.05, metric: true), 105);
    expect(LoadMath.increase(19, 0.025, metric: true), 20);
    // 60 kg shows as 132.3 lb; 5 lb plates make 135 lb next.
    expect(
      LoadMath.increase(60, 0.025, metric: false) * lb,
      closeTo(135, 1e-9),
    );
  });

  test('cuts round to the nearest load, not a step below it', () {
    expect(LoadMath.reduce(50, 0.1, metric: true), 45);
    expect(LoadMath.reduce(11, 0.1, metric: true), 10);
    expect(LoadMath.reduce(27.5, 0.1, metric: true), 25);
    expect(LoadMath.reduce(52.5, 0.1, metric: true), 47.5);
    expect(LoadMath.reduce(40, 0.2, metric: true), 32.5);
    expect(
      LoadMath.reduce(55 / lb, 0.1, metric: false)! * lb,
      closeTo(50, 1e-9),
    );
  });

  test('light loads are not cut', () {
    expect(LoadMath.reduce(2, 0.1, metric: true), isNull); // two 1 kg steps
    expect(LoadMath.reduce(3, 0.1, metric: true), isNull); // 2.7 rounds to 3
  });

  test('loads within the tolerance are the same', () {
    expect(LoadMath.same(60, 60.0103), isTrue);
    expect(LoadMath.heavier(60.0103, 60), isFalse);
    expect(LoadMath.heavier(60.1, 60), isTrue);
    expect(LoadMath.round(92.1, metric: true), 92.5);
  });
}
