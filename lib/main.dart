import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'store.dart';

void main() => runApp(const BikeSpotApp());
const green = Color(0xFF184D3D);

class BikeSpotApp extends StatelessWidget {
  const BikeSpotApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Bike Spot', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: green),
      scaffoldBackgroundColor: const Color(0xFFF6F5EF),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        minimumSize: const Size(0, 54), backgroundColor: green))),
    home: const HomePage());
}
String dateLabel(DateTime d) {
  final t = d.toLocal();
  return '${t.day}/${t.month}/${t.year} · ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> {
  ParkingStore? store;
  List<Parking> items = [];
  bool loading = true, busy = false;
  String? error;
  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    setState(() { loading = true; error = null; });
    try {
      store = ParkingStore(await getApplicationDocumentsDirectory());
      final data = await store!.load();
      if (mounted) setState(() => items = data);
    } catch (_) { if (mounted) setState(() => error = 'Could not read your saved spots. Your data has not been changed.'); }
    if (mounted) setState(() => loading = false);
  }
  Future<void> commit(List<Parking> next) async {
    setState(() => busy = true);
    try {
      await store!.save(next);
      if (mounted) setState(() => items = next);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not save. Your previous spot is still kept. Please try again.')));
    } finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> edit([Parking? current]) async {
    final result = await Navigator.of(context).push<Parking>(MaterialPageRoute(
      builder: (_) => SpotEditor(existing: current)));
    if (result != null && mounted) {
      await commit([result, ...items.where((p) => p.id != result.id)]);
    }
  }
  Future<bool> confirm(String title, String detail) async => await showDialog<bool>(
    context: context, builder: (c) => AlertDialog(title: Text(title), content: Text(detail),
      actions: [TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Confirm'))])) ?? false;
  @override
  Widget build(BuildContext context) {
    final active = items.where((p) => p.collectedAt == null).firstOrNull;
    final history = items.where((p) => p.collectedAt != null).toList();
    return Scaffold(appBar: AppBar(title: const Text('Bike Spot'), backgroundColor: Colors.transparent,
      actions: [IconButton(tooltip: 'About', onPressed: () => showAboutDialog(context: context,
        applicationName: 'Bike Spot', applicationVersion: '1.0.0', children: const [
          Text('Your everyday parking notebook. Spots and photos are saved on this device. No account needed. Uninstalling the app may remove them.')]),
        icon: const Icon(Icons.info_outline))]),
      body: SafeArea(child: loading ? const Center(child: CircularProgressIndicator()) : error != null
        ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min,
          children: [Text(error!), TextButton(onPressed: load, child: const Text('Retry'))])))
        : AbsorbPointer(absorbing: busy, child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(padding: const EdgeInsets.all(24), children: [
            const Text('LESS SEARCHING. MORE CYCLING.', style: TextStyle(fontSize: 11, letterSpacing: 2, color: green)),
            const SizedBox(height: 12),
            Text(active == null ? 'Ready for your commute?' : 'Your bike is waiting.',
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, height: 1.1)),
            const SizedBox(height: 8),
            const Text('Leuven station · Your daily bike companion'),
            const SizedBox(height: 28),
            if (active == null) ...[
              Container(padding: const EdgeInsets.all(32), decoration: BoxDecoration(color: const Color(0xFFE1EADB),
                borderRadius: BorderRadius.circular(24)), child: const Column(children: [
                  Icon(Icons.pedal_bike, size: 88, color: green), SizedBox(height: 16),
                  Text('A little note. An easy ride home.', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8), Text('Save your row, rack or a quick photo before catching your train.', textAlign: TextAlign.center)])),
              const SizedBox(height: 20),
              FilledButton.icon(onPressed: () => edit(), icon: const Icon(Icons.add_location_alt_outlined), label: const Text('Park my bike')),
            ] else ...[
              SpotCard(spot: active), const SizedBox(height: 16),
              FilledButton.icon(onPressed: () async {
                if (await confirm('Bike collected?', 'Move this spot to your parking history.') && mounted) {
                  await commit(items.map((p) => p.id == active.id ? p.collect() : p).toList());
                }
              }, icon: const Icon(Icons.check), label: const Text('Got my bike')),
              TextButton.icon(onPressed: () => edit(active), icon: const Icon(Icons.edit_outlined), label: const Text('Edit parking spot')),
            ],
            if (busy) const LinearProgressIndicator(),
            const SizedBox(height: 28),
            Row(children: [const Expanded(child: Text('Previous spots', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold))),
              if (history.isNotEmpty) TextButton(onPressed: () async {
                if (await confirm('Clear history?', 'Permanently remove all collected spots and their photos. Your current spot stays saved.') && mounted) {
                  await commit(items.where((p) => p.collectedAt == null).toList());
                }
              }, child: const Text('Clear'))]),
            if (history.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('Collected bikes will appear here.')),
            ...history.map((p) => Card(child: ListTile(leading: const Icon(Icons.pedal_bike),
              title: Text(p.place), subtitle: Text(dateLabel(p.parkedAt)), trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('Previous spot')), body: SingleChildScrollView(
                  padding: const EdgeInsets.all(24), child: SpotCard(spot: p)))))))),
            const SizedBox(height: 20), const Text('Saved on your phone · Available offline', textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 12)),
          ]))))));
  }
}

class SpotCard extends StatelessWidget {
  final Parking spot;
  const SpotCard({super.key, required this.spot});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: green, borderRadius: BorderRadius.circular(24)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(spot.collectedAt == null ? 'PARKED HERE' : 'PREVIOUSLY PARKED', style: const TextStyle(color: Color(0xFFC5DCAD), letterSpacing: 2, fontSize: 11)),
      const SizedBox(height: 12), Text(spot.place, style: const TextStyle(color: Colors.white, fontSize: 30, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8), Text('Parked ${dateLabel(spot.parkedAt)}', style: const TextStyle(color: Colors.white70)),
      if (spot.collectedAt != null) Text('Collected ${dateLabel(spot.collectedAt!)}', style: const TextStyle(color: Colors.white70)),
      const SizedBox(height: 24), Wrap(spacing: 12, runSpacing: 12, children: [
        for (final entry in {'Level': spot.level, 'Row': spot.row, 'Rack': spot.rack}.entries)
          if (entry.value.isNotEmpty) Chip(label: Text('${entry.key}  ${entry.value}'))]),
      if (spot.notes.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(spot.notes, style: const TextStyle(color: Colors.white, fontSize: 17))),
      if (spot.photo != null) Padding(padding: const EdgeInsets.only(top: 20), child: GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute<void>(builder: (_) => Scaffold(
          backgroundColor: Colors.black, appBar: AppBar(title: const Text('Parking photo')),
          body: Center(child: InteractiveViewer(minScale: 0.5, maxScale: 5, child: Image.memory(base64Decode(spot.photo!))))))),
        child: ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.memory(base64Decode(spot.photo!),
          width: double.infinity, height: 220, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Text('Photo unavailable', style: TextStyle(color: Colors.white))))))
    ]));
}

class SpotEditor extends StatefulWidget {
  final Parking? existing;
  const SpotEditor({super.key, this.existing});
  @override
  State<SpotEditor> createState() => _SpotEditorState();
}
class _SpotEditorState extends State<SpotEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController place, level, row, rack, notes;
  String? photo;
  bool picking = false;
  @override
  void initState() {
    super.initState(); final p = widget.existing;
    place = TextEditingController(text: p?.place ?? 'Leuven station · P2');
    level = TextEditingController(text: p?.level ?? ''); row = TextEditingController(text: p?.row ?? '');
    rack = TextEditingController(text: p?.rack ?? ''); notes = TextEditingController(text: p?.notes ?? ''); photo = p?.photo;
    if (Platform.isAndroid) recoverPhoto();
  }
  Future<void> recoverPhoto() async {
    try {
      final lost = await ImagePicker().retrieveLostData();
      if (lost.files?.isNotEmpty ?? false) await acceptPhoto(lost.files!.first);
    } catch (_) { message('Could not recover the photo. Please add it again.'); }
  }
  Future<void> acceptPhoto(XFile file) async {
    final bytes = await file.readAsBytes();
    if (bytes.length > 8 * 1024 * 1024) { message('Choose a smaller photo (under 8 MB).'); return; }
    if (mounted) setState(() => photo = base64Encode(bytes));
  }
  void message(String text) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text))); }
  Future<void> pick(ImageSource source) async {
    setState(() => picking = true);
    try {
      final image = await ImagePicker().pickImage(source: source, maxWidth: 1600, maxHeight: 1600, imageQuality: 75);
      if (image != null) await acceptPhoto(image);
    } catch (_) { message('Could not open the camera or photos. Check this app’s permissions in Settings.'); }
    finally { if (mounted) setState(() => picking = false); }
  }
  @override
  void dispose() { for (final c in [place, level, row, rack, notes]) { c.dispose(); } super.dispose(); }
  Widget field(TextEditingController c, String label, {String? hint, int lines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 16), child: TextFormField(controller: c, maxLines: lines,
      maxLength: lines > 1 ? 500 : 80, textCapitalization: TextCapitalization.sentences,
      decoration: InputDecoration(labelText: label, hintText: hint, counterText: ''),
      validator: (v) => c == place && (v == null || v.trim().isEmpty) ? 'Enter a parking location' : null));
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.existing == null ? 'Park my bike' : 'Edit spot')),
    body: SafeArea(child: Form(key: form, child: ListView(padding: const EdgeInsets.all(24), children: [
      const Text('Remember the little details.', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8), const Text('Only the location is required. A row or photo makes finding your bike easier.'),
      const SizedBox(height: 24), field(place, 'Parking location'),
      field(level, 'Level (optional)', hint: 'e.g. lower level'),
      field(row, 'Row / zone (optional)', hint: 'e.g. B'), field(rack, 'Rack / number (optional)', hint: 'e.g. 142'),
      field(notes, 'Landmark or notes (optional)', hint: 'Near the stairs, upper rack…', lines: 3),
      if (photo != null) ...[
        ClipRRect(borderRadius: BorderRadius.circular(16), child: Image.memory(base64Decode(photo!), height: 200, fit: BoxFit.cover)),
        TextButton(onPressed: picking ? null : () => setState(() => photo = null), child: const Text('Remove photo'))],
      Wrap(spacing: 12, children: [OutlinedButton.icon(onPressed: picking ? null : () => pick(ImageSource.camera),
        icon: const Icon(Icons.camera_alt_outlined), label: const Text('Take photo')),
        OutlinedButton.icon(onPressed: picking ? null : () => pick(ImageSource.gallery),
        icon: const Icon(Icons.photo_outlined), label: const Text('Choose photo'))]),
      if (picking) const LinearProgressIndicator(), const SizedBox(height: 24),
      FilledButton(onPressed: picking ? null : () {
        if (!form.currentState!.validate()) return;
        final now = DateTime.now();
        Navigator.pop(context, Parking(id: widget.existing?.id ?? now.microsecondsSinceEpoch.toString(),
          place: place.text.trim(), level: level.text.trim(), row: row.text.trim(), rack: rack.text.trim(),
          notes: notes.text.trim(), photo: photo, parkedAt: widget.existing?.parkedAt ?? now));
      }, child: const Text('Save parking spot')), const SizedBox(height: 20),
    ]))));
}
