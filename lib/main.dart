import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import 'store.dart';
import 'trains.dart';
import 'package:timezone/data/latest.dart' as tzdata;

void main() {
  tzdata.initializeTimeZones();
  runApp(const BikeSpotApp());
}

class BikeSpotApp extends StatelessWidget {
  const BikeSpotApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Leuven Conmute',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF184D3D)),
          scaffoldBackgroundColor: const Color(0xFFF6F5EF),
        ),
        home: const CommutePages(),
      );
}

class CommutePages extends StatefulWidget {
  const CommutePages({super.key});
  @override
  State<CommutePages> createState() => _CommutePagesState();
}
class _CommutePagesState extends State<CommutePages> {
  final _pages = PageController();
  int _index = 0;
  @override
  void dispose() { _pages.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    body: PageView(
      controller: _pages,
      onPageChanged: (index) => setState(() => _index = index),
      children: const [ParkingPage(), TrainsPage()],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _index,
      onDestinationSelected: (index) => _pages.animateToPage(index,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut),
      destinations: const [
        NavigationDestination(icon: Icon(Icons.pedal_bike), label: 'Bike'),
        NavigationDestination(icon: Icon(Icons.train_outlined), label: 'Trains'),
      ],
    ),
  );
}
class TrainsPage extends StatelessWidget {
  const TrainsPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Trains')),
    body: const SafeArea(child: SingleChildScrollView(
      padding: EdgeInsets.all(16), child: TrainPanel())),
  );
}

class ParkingPage extends StatefulWidget {
  const ParkingPage({super.key});

  @override
  State<ParkingPage> createState() => _ParkingPageState();
}

class _ParkingPageState extends State<ParkingPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  ParkingStore? _store;
  List<Parking> _items = [];
  Parking? _saved;
  String _parking = 'P2';
  final _section = TextEditingController();
  Uint8List? _photo;
  bool _loading = true;
  bool _busy = false;
  bool _dirty = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _section.dispose();
    super.dispose();
  }

  String _spotLabel(Parking spot) => spot.row.isEmpty
      ? spot.place
      : '${spot.place} · Section ${spot.row}';

  void _message(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final store = ParkingStore(await getApplicationDocumentsDirectory());
      final items = await store.load();
      final active = items.where((p) => p.collectedAt == null).firstOrNull;
      final lot = active == null
          ? null
          : RegExp(r'\bP[123]\b', caseSensitive: false)
              .firstMatch(active.place)
              ?.group(0)
              ?.toUpperCase();
      Uint8List? photo;
      if (active?.photo != null) {
        try {
          photo = base64Decode(active!.photo!);
        } on FormatException {
          _message('The saved photo could not be opened. You can take a new one.');
        }
      }
      if (!mounted) return;
      setState(() {
        _store = store;
        _items = items;
        _saved = active;
        _parking = lot ?? 'P2';
        _section.text = active?.row ?? '';
        _photo = photo;
        _loading = false;
        _busy = Platform.isAndroid;
      });
      // Android may restart the app while the camera is open.
      if (Platform.isAndroid) {
        try {
          final lost = await ImagePicker().retrieveLostData();
          if (lost.files?.isNotEmpty ?? false) {
            await _acceptPhoto(lost.files!.first);
            _message('Photo recovered. Check your parking choice and tap Save.');
          } else if (lost.exception != null) {
            _message('The photo was not recovered. Please try again.');
          }
        } catch (_) {
          _message('Could not recover the camera photo. Please try again.');
        } finally {
          if (mounted) setState(() => _busy = false);
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your parking spot. Please try again.';
      });
    }
  }

  Future<void> _acceptPhoto(XFile file) async {
    final bytes = await file.readAsBytes();
    if (bytes.length > 8 * 1024 * 1024) {
      _message('This photo is too large. Please take another photo.');
      return;
    }
    if (!mounted) return;
    setState(() {
      _photo = bytes;
      _dirty = true;
    });
  }

  Future<void> _takePhoto() async {
    setState(() => _busy = true);
    try {
      final file = await ImagePicker().pickImage(
        source: ImageSource.camera,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 75,
      );
      if (file != null) await _acceptPhoto(file);
    } catch (_) {
      _message('Could not open the camera. Check camera permission in Settings.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final now = DateTime.now();
    final spot = Parking(
      id: _saved?.id ?? now.microsecondsSinceEpoch.toString(),
      place: 'Leuven station · $_parking',
      level: '',
      row: _section.text.trim(),
      rack: '',
      notes: '',
      parkedAt: now,
      photo: _photo == null ? null : base64Encode(_photo!),
    );
    // Keep older records compatible with store.dart without showing history.
    final next = [spot, ..._items.where((p) => p.collectedAt != null)];
    try {
      await _store!.save(next);
      if (!mounted) return;
      setState(() {
        _items = next;
        _saved = spot;
        _dirty = false;
      });
      _message('Saved: ${_spotLabel(spot)}');
    } catch (_) {
      _message('Could not save. Your previous parking spot is still saved.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openPhoto() {
    final photo = _photo;
    if (photo == null) return;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Parking photo')),
        backgroundColor: Colors.black,
        body: Center(
          child: InteractiveViewer(
            maxScale: 5,
            child: Image.memory(photo,
                errorBuilder: (_, __, ___) => const Text('Photo unavailable',
                    style: TextStyle(color: Colors.white))),
          ),
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
        appBar: AppBar(
          title: const Text('Leuven Conmute'),
          backgroundColor: Colors.transparent,
        ),
        body: SafeArea(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_error!),
                          TextButton(onPressed: _load, child: const Text('Retry')),
                        ],
                      ),
                    )
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: ListView(
                          padding: const EdgeInsets.all(24),
                          children: [

                            const Icon(Icons.pedal_bike,
                                size: 72, color: Color(0xFF184D3D)),
                            const SizedBox(height: 16),
                            const Text('Leuven station',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                    fontSize: 28, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 12),
                            Text(
                              _saved == null
                                  ? 'Where did you park?'
                                  : 'Saved: ${_spotLabel(_saved!)}',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 28),
                            SegmentedButton<String>(
                              segments: const [
                                ButtonSegment(value: 'P1', label: Text('P1')),
                                ButtonSegment(value: 'P2', label: Text('P2')),
                                ButtonSegment(value: 'P3', label: Text('P3')),
                              ],
                              selected: {_parking},
                              onSelectionChanged: _busy
                                  ? null
                                  : (values) => setState(() {
                                        if (_parking != values.first) {
                                          _parking = values.first;
                                          // Reset details when switching to a different parking area.
                                          _section.clear();
                                          _photo = null;
                                          _dirty = true;
                                        }
                                      }),
                            ),
                            const SizedBox(height: 24),
                            TextField(
                              controller: _section,
                              enabled: !_busy,
                              keyboardType: TextInputType.text,
                              textCapitalization: TextCapitalization.characters,
                              textInputAction: TextInputAction.done,
                              maxLength: 30,
                              decoration: const InputDecoration(
                                labelText: 'Section / column number',
                                hintText: 'e.g. 24 or B12',
                                helperText: 'Number shown on the nearest column (optional)',
                                border: OutlineInputBorder(),
                                counterText: '',
                              ),
                              onChanged: (_) => setState(() => _dirty = true),
                            ),
                            const SizedBox(height: 24),
                            if (_photo != null) ...[
                              Semantics(
                                label: 'Parking photo. Tap to enlarge.',
                                button: true,
                                child: GestureDetector(
                                  onTap: _openPhoto,
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(16),
                                    child: Image.memory(_photo!,
                                        height: 260,
                                        width: double.infinity,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => const SizedBox(
                                            height: 100,
                                            child: Center(child: Text('Photo unavailable')))),
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(() {
                                          _photo = null;
                                          _dirty = true;
                                        }),
                                child: const Text('Remove photo'),
                              ),
                            ],
                            OutlinedButton.icon(
                              onPressed: _busy ? null : _takePhoto,
                              icon: const Icon(Icons.camera_alt_outlined),
                              label: Text(_photo == null
                                  ? 'Take a photo (optional)'
                                  : 'Retake photo'),
                            ),
                            const SizedBox(height: 16),
                            FilledButton(
                              style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(54)),
                              onPressed: _busy ? null : _save,
                              child: const Text('Save parking spot'),
                            ),
                            if (_busy) ...[
                              const SizedBox(height: 16),
                              const LinearProgressIndicator(),
                            ],
                            const SizedBox(height: 12),
                            Text(
                              _dirty ? 'Changes not saved yet' : 'Parking saved on your phone · Trains need internet',
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontSize: 12, color: Colors.black54),
                            ),
                          ],
                        ),
                      ),
                    ),
        ),
      );
  }
}
