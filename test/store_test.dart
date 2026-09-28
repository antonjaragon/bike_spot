import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:bike_spot/store.dart';

void main() {
  late Directory dir;
  late ParkingStore store;
  setUp(() async { dir = await Directory.systemTemp.createTemp('bike_spot_test'); store = ParkingStore(dir); });
  tearDown(() async { await dir.delete(recursive: true); });
  Parking spot() => Parking(id: '1', place: 'Leuven station · P2', level: '-1',
    row: 'B', rack: '42', notes: 'By the stairs', photo: 'aGVsbG8=', parkedAt: DateTime.utc(2026, 9, 28));
  test('new install starts empty', () async { expect(await store.load(), isEmpty); });
  test('spot, photo and collected state survive reload and replacement', () async {
    await store.save([spot()]);
    final loaded = (await ParkingStore(dir).load()).single;
    expect(loaded.toJson(), spot().toJson());
    await store.save([loaded.collect()]);
    expect((await store.load()).single.collectedAt, isNotNull);
    await store.save([]);
    expect(await store.load(), isEmpty);
  });
  test('corrupt file is reported and left untouched', () async {
    await store.file.writeAsString('broken');
    await expectLater(store.load(), throwsFormatException);
    expect(await store.file.readAsString(), 'broken');
  });
}
