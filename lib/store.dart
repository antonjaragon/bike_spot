import 'dart:convert';
import 'dart:io';

class Parking {
  final String id, place, level, row, rack, notes;
  final DateTime parkedAt;
  final DateTime? collectedAt;
  final String? photo;
  const Parking({required this.id, required this.place, required this.level,
    required this.row, required this.rack, required this.notes,
    required this.parkedAt, this.collectedAt, this.photo});
  Parking collect() => Parking(id: id, place: place, level: level, row: row,
    rack: rack, notes: notes, parkedAt: parkedAt, collectedAt: DateTime.now(), photo: photo);
  Map<String, dynamic> toJson() => {'id': id, 'place': place, 'level': level,
    'row': row, 'rack': rack, 'notes': notes, 'parkedAt': parkedAt.toIso8601String(),
    'collectedAt': collectedAt?.toIso8601String(), 'photo': photo};
  factory Parking.fromJson(Map<String, dynamic> j) => Parking(
    id: j['id'] as String, place: j['place'] as String, level: j['level'] as String,
    row: j['row'] as String, rack: j['rack'] as String, notes: j['notes'] as String,
    parkedAt: DateTime.parse(j['parkedAt'] as String),
    collectedAt: j['collectedAt'] == null ? null : DateTime.parse(j['collectedAt'] as String),
    photo: j['photo'] as String?);
}

class ParkingStore {
  final Directory directory;
  ParkingStore(this.directory);
  File get file => File('${directory.path}/parking.json');
  Future<List<Parking>> load() async {
    if (!await file.exists()) return [];
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    if (data['version'] != 1) throw const FormatException('Unsupported storage version');
    return (data['items'] as List).map((j) => Parking.fromJson(j as Map<String, dynamic>)).toList();
  }
  Future<void> save(List<Parking> items) async {
    await directory.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode({'version': 1,
      'items': items.map((p) => p.toJson()).toList()}), flush: true);
    await temp.rename(file.path);
  }
}
