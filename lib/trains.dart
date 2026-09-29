import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:timezone/timezone.dart' as tz;

DateTime belgianTime(DateTime time) => tz.TZDateTime.from(time, tz.getLocation('Europe/Brussels'));
bool outboundAt(DateTime time) => belgianTime(time).hour < 12;
String clock(DateTime time) {
  final t = belgianTime(time);
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}
Map<String, dynamic> object(dynamic x) => x is Map ? Map<String, dynamic>.from(x) : {};
List<Map<String, dynamic>> objects(dynamic x) => x is List
    ? x.map(object).toList() : x is Map ? [object(x)] : [];
int number(dynamic x) => int.tryParse('$x') ?? 0;
bool yes(dynamic x) => x == true || '$x' == '1';
DateTime timestamp(dynamic x) {
  final seconds = int.tryParse('$x');
  if (seconds == null || seconds <= 0) throw const FormatException('Missing train time');
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
}

class Journey {
  final Map<String, dynamic> departure, arrival;
  final List<Map<String, dynamic>> vias;
  final List<String> alerts;
  Journey(this.departure, this.arrival, this.vias, this.alerts);
  factory Journey.fromJson(Map<String, dynamic> j) {
    final d = object(j['departure']), a = object(j['arrival']);
    timestamp(d['time']); timestamp(a['time']);
    final vias = objects(object(j['vias'])['via']);
    for (final via in vias) {
      timestamp(object(via['arrival'])['time']);
      timestamp(object(via['departure'])['time']);
    }
    final alerts = <String>{};
    for (final part in [j, d, a, ...vias.expand((v) => [object(v['arrival']), object(v['departure'])])]) {
      for (final alert in objects(object(part['alerts'])['alert'])) {
        final title = '${alert['header'] ?? alert['lead'] ?? ''}';
        if (title.isNotEmpty) alerts.add(title);
      }
    }
    return Journey(d, a, vias, alerts.toList());
  }
  DateTime get expectedDeparture => timestamp(departure['time']).add(Duration(seconds: number(departure['delay'])));
  DateTime get expectedArrival => timestamp(arrival['time']).add(Duration(seconds: number(arrival['delay'])));
  bool get canceled => [departure, arrival, ...vias.expand((v) => [object(v['arrival']), object(v['departure'])])]
      .any((s) => yes(s['canceled']));
  String get identity => '${departure['vehicle']}|${departure['time']}|${arrival['vehicle']}|${arrival['time']}';
  bool get left => yes(departure['left']);
  List<Leg> get legs {
    final out = <Leg>[];
    var from = departure;
    var name = stationName(departure['station']);
    for (final via in vias) {
      out.add(Leg(from, object(via['arrival']), name, stationName(via['station'], 'Transfer station')));
      from = object(via['departure']);
      name = stationName(via['station'], 'Transfer station');
    }
    out.add(Leg(from, arrival, name, stationName(arrival['station'])));
    return out;
  }
}

class Leg {
  final Map<String, dynamic> from, to;
  final String fromName, toName;
  Leg(this.from, this.to, this.fromName, this.toName);
  DateTime get departs => timestamp(from['time']).add(Duration(seconds: number(from['delay'])));
  DateTime get arrives => timestamp(to['time']).add(Duration(seconds: number(to['delay'])));
  bool get canceled => yes(from['canceled']) || yes(to['canceled']);
}

bool platformChanged(Map<String, dynamic> p) => '${object(p['platforminfo'])['normal']}' == '0';
bool isDelayed(Map<String, dynamic> p) => number(p['delay']) > 0;
String platformLabel(Map<String, dynamic> p) => 'Platform ${p['platform'] ?? '?'}${platformChanged(p) ? ' · changed' : ''}';
String serviceName(Map<String, dynamic> p) => yes(p['walking']) ? 'Walk'
    : '${object(p['vehicleinfo'])['shortname'] ?? p['vehicle'] ?? 'Train'}'.replaceFirst('BE.NMBS.', '');
String stationName(dynamic x, [String fallback = 'Station']) {
  final s = '${x ?? ''}';
  return s.isEmpty ? fallback : s;
}
String formatDuration(Duration d) => d.inMinutes < 60 ? '${d.inMinutes} min' : '${d.inHours} h ${d.inMinutes % 60} min';

class TrainPanel extends StatefulWidget {
  const TrainPanel({super.key});
  @override
  State<TrainPanel> createState() => _TrainPanelState();
}
class _TrainPanelState extends State<TrainPanel> with WidgetsBindingObserver, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  Journey? _followed;
  String? _followWarning;
  Timer? _timer;
  HttpClient? _client;
  List<Journey> _journeys = [];
  bool _outbound = outboundAt(DateTime.now()), _loading = false, _foreground = true;
  DateTime? _updated;
  DateTime? _anchor; // null = live (from now); otherwise the time being browsed
  DateTime _nextRequest = DateTime.fromMillisecondsSinceEpoch(0); // next automatic refresh
  DateTime _blockedUntil = DateTime.fromMillisecondsSinceEpoch(0); // server asked us to back off (429)
  DateTime _lastFetch = DateTime.fromMillisecondsSinceEpoch(0);
  String? _error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!_foreground) return;
      _syncDirection();
      if (!_loading && !DateTime.now().isBefore(_nextRequest)) _refresh();
      if (mounted) setState(() {});
    });
  }
  void _syncDirection() {
    if (_followed != null || _anchor != null) return;
    final direction = outboundAt(DateTime.now());
    if (direction == _outbound) return;
    setState(() {
      _outbound = direction;
      _journeys = [];
      _updated = null;
      _error = null;
      _nextRequest = DateTime.fromMillisecondsSinceEpoch(0);
    });
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (_foreground) { _syncDirection(); _refresh(); }
  }
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _client?.close(force: true);
    super.dispose();
  }
  // Automatic refreshes follow the schedule in _nextRequest. The refresh button and
  // earlier/later paging bypass that schedule, but always respect a server back-off.
  Future<void> _refresh({bool force = false, bool button = false}) async {
    _syncDirection();
    final t = DateTime.now();
    if (_loading || t.isBefore(_blockedUntil)) return;
    if (!force && !button && t.isBefore(_nextRequest)) return;
    if (button && t.difference(_lastFetch) < const Duration(seconds: 5)) return;
    _lastFetch = t;
    final outbound = _outbound;
    final anchor = _anchor;
    final now = belgianTime(_followed != null ? timestamp(_followed!.departure['time']) : (anchor ?? DateTime.now()));
    String pad(int n) => n.toString().padLeft(2, '0');
    final uri = Uri.https('api.irail.be', '/connections/', {
      'from': outbound ? 'Gent-Dampoort' : 'Leuven',
      'to': outbound ? 'Leuven' : 'Gent-Dampoort',
      'date': '${pad(now.day)}${pad(now.month)}${pad(now.year % 100)}',
      'time': '${pad(now.hour)}${pad(now.minute)}',
      'timesel': 'departure', 'format': 'json', 'lang': 'nl',
      'results': '6', 'alerts': 'true', 'typeOfTransport': 'automatic',
    });
    setState(() { _loading = true; _error = null; });
    _nextRequest = DateTime.now().add(const Duration(minutes: 1));
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    _client = client;
    try {
      final payload = await (() async {
        final request = await client.getUrl(uri);
        request.headers.set(HttpHeaders.userAgentHeader, 'LeuvenCommute/1.2 (personal commute app)');
        request.headers.set(HttpHeaders.acceptHeader, 'application/json');
        final response = await request.close();
        final cacheSeconds = int.tryParse(RegExp(r'max-age=(\d+)')
            .firstMatch(response.headers.value('cache-control') ?? '')?.group(1) ?? '') ?? 60;
        _nextRequest = DateTime.now().add(Duration(seconds: cacheSeconds > 60 ? cacheSeconds : 60));
        if (response.statusCode == 429) {
          final retry = response.headers.value('retry-after') ?? '';
          var wait = int.tryParse(retry) ?? 300;
          try { wait = HttpDate.parse(retry).difference(DateTime.now()).inSeconds; } catch (_) {}
          _blockedUntil = DateTime.now().add(Duration(seconds: wait > 60 ? wait : 60));
          _nextRequest = _blockedUntil;
          throw const HttpException('Timetable service is busy. Please wait before refreshing.');
        }
        if (response.statusCode != 200) throw HttpException('Timetable unavailable (${response.statusCode}). Try again shortly.');
        final body = await response.transform(utf8.decoder).join();
        final json = object(jsonDecode(body));
        if (json.containsKey('error')) throw const FormatException('Timetable service returned an error');
        if (!json.containsKey('connection')) throw const FormatException('Unexpected timetable response');
        return objects(json['connection']).map(Journey.fromJson).toList();
      })().timeout(const Duration(seconds: 20));
      if (!mounted || (_followed == null && (anchor != _anchor || (anchor == null && outbound != outboundAt(DateTime.now()))))) return;
      payload.sort((a, b) => a.expectedDeparture.compareTo(b.expectedDeparture));
      setState(() {
        _journeys = payload;
        _updated = DateTime.now();
        if (_followed != null) {
          final matches = payload.where((j) => j.identity == _followed!.identity);
          if (matches.isNotEmpty) {
            _followed = matches.first;
            _followWarning = null;
          } else {
            _followWarning = 'This journey was not returned in the latest update. Showing its last known details; check station displays.';
          }
        }
      });
    } catch (e) {
      if (!mounted || (_followed == null && (anchor != _anchor || (anchor == null && outbound != outboundAt(DateTime.now()))))) return;
      setState(() {
        _journeys = [];
        if (_followed != null) _followWarning = 'Live update failed. Showing last known journey details.';
        _error = e is HttpException ? e.message : 'Could not load trains. Check your connection and try again.';
      });
    } finally {
      client.close(force: true);
      if (mounted) {
        setState(() => _loading = false);
        _syncDirection();
        if (_foreground && !DateTime.now().isBefore(_nextRequest)) _refresh();
      }
    }
  }

  void _goTo(DateTime? anchor) {
    if (_followed != null || _loading || DateTime.now().isBefore(_blockedUntil)) return;
    setState(() { _anchor = anchor; _journeys = []; _updated = null; _error = null; });
    if (anchor == null) _syncDirection();
    _refresh(force: true);
  }
  void _page(int direction, List<Journey> shown) {
    final DateTime base;
    if (shown.isEmpty) {
      base = (_anchor ?? DateTime.now()).add(Duration(hours: direction));
    } else if (direction > 0) {
      base = shown.last.expectedDeparture.add(const Duration(minutes: 1));
    } else {
      base = shown.first.expectedDeparture.subtract(const Duration(hours: 1));
    }
    _goTo(base);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final now = DateTime.now();
    final blocked = now.isBefore(_blockedUntil);
    final upcoming = _anchor == null
        ? _journeys.where((j) => !j.left && !j.expectedDeparture.isBefore(now)).take(4).toList()
        : _journeys.take(4).toList();
    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.train_outlined), const SizedBox(width: 8),
          const Expanded(child: Text('Next trains', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold))),
          IconButton(tooltip: blocked ? 'Timetable service is busy, try again later' : 'Refresh trains',
            onPressed: _loading || blocked ? null : () => _refresh(button: true), icon: const Icon(Icons.refresh))]),
        Text(_outbound ? 'Gent-Dampoort → Leuven' : 'Leuven → Gent-Dampoort',
          style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(_followed != null ? 'Following your journey · Automatic direction switch paused'
            : _anchor != null ? 'Browsing other times · Automatic direction switch paused'
            : 'Swipe right for your bike · Direction switches at 12:00', style: const TextStyle(fontSize: 12)),
        if (_followed == null) Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          TextButton.icon(onPressed: _loading || blocked ? null : () => _page(-1, upcoming),
            icon: const Icon(Icons.chevron_left), label: const Text('Earlier')),
          if (_anchor != null) TextButton(onPressed: _loading || blocked ? null : () => _goTo(null), child: const Text('Now')),
          TextButton(onPressed: _loading || blocked ? null : () => _page(1, upcoming),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [Text('Later'), Icon(Icons.chevron_right)])),
        ]),
        const SizedBox(height: 4),
        if (_loading) const LinearProgressIndicator(),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_error!)),
        if (_followed == null && !_loading && _error == null && upcoming.isEmpty) const Text('No upcoming journeys returned. Refresh shortly.'),
        if (_followed != null) ...[
          const SizedBox(height: 12),
          const Text('YOUR JOURNEY', style: TextStyle(fontWeight: FontWeight.bold)),
          if (_followWarning != null) Container(
            padding: const EdgeInsets.all(12), color: const Color(0xFFFCE8E6),
            child: Text(_followWarning!)),
          _JourneyTile(journey: _followed!, following: true),
          TextButton(onPressed: _loading ? null : () {
            setState(() { _followed = null; _followWarning = null; _journeys = []; });
            _syncDirection();
            _refresh(force: true);
          }, child: const Text('Stop following')),
        ] else ...upcoming.map((j) => _JourneyTile(journey: j,
          onFollow: _loading || j.canceled ? null : () {
            setState(() { _followed = j; _followWarning = null; });
          })),
        const SizedBox(height: 8),
        Text(_updated == null ? 'NMBS/SNCB connections via iRail' : 'Updated ${clock(_updated!)} · ${now.difference(_updated!).inSeconds}s ago · via iRail',
          style: const TextStyle(fontSize: 12, color: Colors.black54)),
        const Text('Live updates via iRail; may differ from NMBS. Check station displays.', style: TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    )));
  }
}

const softRed = Color(0xFFFCE8E6);
const redInk = Color(0xFF9C3934);

class _JourneyTile extends StatelessWidget {
  final Journey journey;
  final VoidCallback? onFollow;
  final bool following;
  const _JourneyTile({required this.journey, this.onFollow, this.following = false});
  Widget badge(String text, {bool warning = false}) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: warning ? softRed : const Color(0xFFE8EFE9),
      borderRadius: BorderRadius.circular(8)),
    child: Text(text, style: TextStyle(color: warning ? redInk : const Color(0xFF184D3D), fontSize: 12)));
  Widget stop(String label, Map<String, dynamic> part) {
    final scheduled = timestamp(part['time']);
    final delay = number(part['delay']);
    final expected = scheduled.add(Duration(seconds: delay));
    final warning = isDelayed(part) || platformChanged(part) || yes(part['canceled']);
    final known = part['delay'] != null;
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5), padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: warning ? softRed : const Color(0xFFF4F6F4),
        borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        Wrap(spacing: 10, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(clock(scheduled), style: TextStyle(fontSize: 20,
            decoration: delay != 0 ? TextDecoration.lineThrough : null, color: Colors.black54)),
          if (delay != 0) Text(clock(expected), style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold, color: redInk)),
          Text(yes(part['canceled']) ? 'Cancelled' : !known ? 'Live delay unavailable'
              : delay > 0 ? '+${(delay / 60).ceil()} min' : 'No delay reported',
            style: TextStyle(color: warning ? redInk : const Color(0xFF184D3D))),
        ]),
        Text(platformLabel(part), style: TextStyle(color: platformChanged(part) ? redInk : null)),
      ]),
    );
  }
  @override
  Widget build(BuildContext context) {
    final j = journey;
    final parts = [j.departure, j.arrival, ...j.vias.expand((v) => [object(v['arrival']), object(v['departure'])])];
    final disrupted = j.canceled || parts.any((p) => isDelayed(p) || platformChanged(p)) || j.alerts.isNotEmpty;
    final day = belgianTime(j.expectedDeparture), today = belgianTime(DateTime.now());
    final otherDay = day.year != today.year || day.month != today.month || day.day != today.day;
    final minutes = j.expectedDeparture.difference(DateTime.now()).inMinutes;
    final arrived = yes(j.arrival['arrived']);
    return Container(margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(border: Border.all(color: disrupted ? const Color(0xFFE9B9B5) : const Color(0xFFDDE5DE)),
        borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: following ? null : () => showJourneyDetails(context, j, onFollow),
        child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: Wrap(spacing: 8, runSpacing: 8, children: [
              badge(serviceName(j.departure)),
              badge(j.vias.isEmpty ? 'Direct' : '${j.vias.length} transfer(s)'),
              if (j.canceled) badge('Journey cancelled', warning: true),
              if (j.alerts.isNotEmpty) badge('Service alert', warning: true),
            ])),
            if (!following) const Icon(Icons.chevron_right, color: Colors.black45),
          ]),
          const SizedBox(height: 10),
          if (otherDay) Text('${day.day}/${day.month}/${day.year}'),
          if (!j.canceled) Text(arrived ? 'Arrived' : j.left ? 'Departed' : minutes < 0
              ? 'Scheduled departure passed · awaiting status' : minutes == 0 ? 'Due now' : 'Departs in $minutes min'),
          if (following) ...[
            const SizedBox(height: 8),
            JourneyTimeline(journey: j),
          ] else ...[
            stop('Departure', j.departure),
            stop('Arrival', j.arrival),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: onFollow, icon: const Icon(Icons.near_me_outlined), label: const Text('Follow this journey'))),
          ],
        ])),
      ),
    );
  }
}

void showJourneyDetails(BuildContext context, Journey j, VoidCallback? onFollow) {
  final legs = j.legs;
  final day = belgianTime(j.expectedDeparture);
  showModalBottomSheet<void>(
    context: context, isScrollControlled: true, showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false, initialChildSize: 0.8, minChildSize: 0.4, maxChildSize: 0.95,
      builder: (ctx, controller) => ListView(
        controller: controller, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          Text('${legs.first.fromName} → ${legs.last.toName}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('${day.day}/${day.month}/${day.year} · ${formatDuration(j.expectedArrival.difference(j.expectedDeparture))} · '
              '${j.vias.isEmpty ? 'Direct' : '${j.vias.length} transfer(s)'}', style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 16),
          JourneyTimeline(journey: j),
          if (onFollow != null) Padding(padding: const EdgeInsets.only(top: 12), child: FilledButton.icon(
            onPressed: () { Navigator.pop(ctx); onFollow(); },
            icon: const Icon(Icons.near_me_outlined), label: const Text('Follow this journey'))),
        ],
      ),
    ),
  );
}

class JourneyTimeline extends StatelessWidget {
  final Journey journey;
  const JourneyTimeline({super.key, required this.journey});
  static const green = Color(0xFF184D3D);

  Widget _row({required Widget time, required Widget body, bool dot = true, bool line = true}) => IntrinsicHeight(
    child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SizedBox(width: 58, child: time),
      SizedBox(width: 28, child: Column(children: [
        if (dot) Container(margin: const EdgeInsets.only(top: 4), width: 14, height: 14,
          decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, border: Border.all(color: green, width: 3))),
        if (line) Expanded(child: Container(width: 3, color: const Color(0xFFB9CFC4))),
      ])),
      Expanded(child: body),
    ]));

  Widget _time(Map<String, dynamic> p) {
    final scheduled = timestamp(p['time']);
    final delay = number(p['delay']);
    return Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
      Text(clock(scheduled.add(Duration(seconds: delay))),
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: delay > 0 ? redInk : null)),
      if (delay != 0) Text(clock(scheduled), style: const TextStyle(fontSize: 12, color: Colors.black54, decoration: TextDecoration.lineThrough)),
    ]);
  }

  Widget _stop(String name, Map<String, dynamic> p) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 6),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      Text(platformLabel(p), style: TextStyle(fontSize: 13, color: platformChanged(p) ? redInk : Colors.black54)),
      if (yes(p['canceled'])) const Text('Cancelled', style: TextStyle(color: redInk, fontWeight: FontWeight.bold)),
    ]));

  Widget _transfer(Leg arriving, Leg next) {
    final wait = next.departs.difference(arriving.arrives).inMinutes;
    return Padding(padding: const EdgeInsets.fromLTRB(4, 4, 0, 12),
      child: Text(wait < 0 ? 'Connection at risk · departure before arrival'
          : 'Change trains · $wait min',
        style: TextStyle(fontSize: 13, color: wait < 4 ? redInk : Colors.black54)));
  }

  Widget _legInfo(Leg leg) {
    final towards = object(leg.from['direction'])['name'];
    return Container(
      width: double.infinity, margin: const EdgeInsets.fromLTRB(4, 4, 0, 10), padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: leg.canceled ? softRed : const Color(0xFFF4F6F4), borderRadius: BorderRadius.circular(10)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(serviceName(leg.from), style: const TextStyle(fontWeight: FontWeight.bold)),
        if (towards != null) Text('Towards $towards', style: const TextStyle(fontSize: 13)),
        Text(leg.canceled ? 'Cancelled' : formatDuration(leg.arrives.difference(leg.departs)),
          style: TextStyle(fontSize: 13, color: leg.canceled ? redInk : Colors.black54)),
      ]));
  }

  @override
  Widget build(BuildContext context) {
    final legs = journey.legs;
    final rows = <Widget>[
      _row(time: _time(legs.first.from), body: _stop(legs.first.fromName, legs.first.from)),
    ];
    for (var i = 0; i < legs.length; i++) {
      final leg = legs[i];
      rows.add(_row(time: const SizedBox.shrink(), body: _legInfo(leg), dot: false));
      if (i < legs.length - 1) {
        final next = legs[i + 1];
        rows.add(_row(time: _time(leg.to),
          body: _stop('${leg.toName} · Arrive on ${serviceName(leg.from)}', leg.to)));
        rows.add(_row(time: const SizedBox.shrink(), body: _transfer(leg, next), dot: false));
        rows.add(_row(time: _time(next.from),
          body: _stop('${next.fromName} · Depart on ${serviceName(next.from)}', next.from)));

      } else {
        rows.add(_row(time: _time(leg.to), body: _stop(leg.toName, leg.to), line: false));
      }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ...rows,
      for (final alert in journey.alerts) Container(width: double.infinity,
        margin: const EdgeInsets.only(top: 8), padding: const EdgeInsets.all(12),
        color: softRed, child: Text(alert, style: const TextStyle(color: redInk))),
    ]);
  }
}
