import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as data;
import 'package:bike_spot/trains.dart';

void main() {
  setUpAll(data.initializeTimeZones);
  test('noon switch uses Belgium summer time even on a UTC device', () {
    expect(outboundAt(DateTime.utc(2026, 9, 28, 9, 59)), isTrue);
    expect(outboundAt(DateTime.utc(2026, 9, 28, 10)), isFalse);
  });
  test('noon switch uses Belgium winter time', () {
    expect(outboundAt(DateTime.utc(2026, 12, 1, 10, 59)), isTrue);
    expect(outboundAt(DateTime.utc(2026, 12, 1, 11)), isFalse);
  });
  test('midnight and daylight saving time conversions', () {
    expect(outboundAt(DateTime.utc(2026, 9, 28, 22)), isTrue);
    expect(clock(DateTime.utc(2026, 3, 29, 0, 59)), '01:59');
    expect(clock(DateTime.utc(2026, 3, 29, 1)), '03:00');
    expect(clock(DateTime.utc(2026, 10, 25, 1)), '02:00');
  });
  // Explicit nested types match decoded JSON and allow numeric/string API values.
  Map<String, dynamic> fixture() => {
    'departure': <String, dynamic>{'time': '1790582400', 'delay': '180', 'left': '0', 'canceled': '0'},
    'arrival': <String, dynamic>{'time': 1790586000, 'delay': 300, 'canceled': 0},
    'vias': <String, dynamic>{'via': <Map<String, dynamic>>[{'station': 'Brussel-Noord',
      'arrival': <String, dynamic>{'time': '1790584000', 'canceled': '0'},
      'departure': <String, dynamic>{'time': '1790584300', 'canceled': '1'}}]},
  };
  test('delays accept string and number fields; cancellation includes transfers', () {
    final j = Journey.fromJson(fixture());
    expect(j.expectedDeparture.millisecondsSinceEpoch, 1790582580000);
    expect(j.expectedArrival.millisecondsSinceEpoch, 1790586300000);
    expect(j.canceled, isTrue);
    expect(j.left, isFalse);
    expect(j.vias.single['station'], 'Brussel-Noord');
  });
  test('direct journey may omit vias and alerts', () {
    final raw = fixture()..remove('vias');
    final j = Journey.fromJson(raw);
    expect(j.vias, isEmpty);
    expect(j.alerts, isEmpty);
    expect(j.canceled, isFalse);
  });
  test('invalid time rejected rather than shown as midnight in 1970', () {
    final raw = fixture();
    raw['departure']['time'] = 'invalid';
    expect(() => Journey.fromJson(raw), throwsFormatException);
  });
  test('followed journey identity stays stable when real-time delays change', () {
    final original = Journey.fromJson(fixture());
    final updated = fixture();
    updated['departure']['delay'] = '600';
    updated['arrival']['delay'] = '900';
    final refreshed = Journey.fromJson(updated);
    expect(refreshed.identity, original.identity);
    expect(refreshed.expectedDeparture, isNot(original.expectedDeparture));
  });
  test('different scheduled journey is not silently substituted when following', () {
    final original = Journey.fromJson(fixture());
    final different = fixture();
    different['departure']['time'] = '1790583000';
    expect(Journey.fromJson(different).identity, isNot(original.identity));
  });

}
