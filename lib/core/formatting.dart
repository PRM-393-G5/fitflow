/// Display helpers shared across features.
library;

/// 10000 → "10,000" (rounded; keeps a leading minus).
String thousands(num value) {
  final digits = value.round().abs().toString();
  final buffer = StringBuffer(value.round() < 0 ? '-' : '');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Monday-first short weekday names (`DateTime.weekday - 1` indexes it).
const weekdayNames = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Month names (`DateTime.month - 1` indexes it).
const monthNames = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
