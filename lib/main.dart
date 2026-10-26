// MoonPomo 2 — cute moon tamagotchi + pomodoro planner.
// Floating moon over other apps, notifications, closet, stats. Single file.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

// ───────────────────────── palette ─────────────────────────
const kBg0 = Color(0xFF0A0E2A);
const kBg1 = Color(0xFF1C1B4B);
const kBg2 = Color(0xFF3A2A6B);
const kGold = Color(0xFFFFD98A);
const kPink = Color(0xFFFF9EC4);
const kLilac = Color(0xFFB9A6FF);
const kMint = Color(0xFF8FE3CF);
const kInk = Color(0xFF3B2F5C);

class Skin {
  const Skin(this.name, this.cost, this.hi, this.mid, this.lo);
  final String name;
  final int cost;
  final Color hi, mid, lo;
}

const skins = [
  Skin('Golden', 0, Color(0xFFFFF8DC), Color(0xFFFFE08A), Color(0xFFF5C25B)),
  Skin('Rose', 30, Color(0xFFFFF0F5), Color(0xFFFFC2D9), Color(0xFFF59AB8)),
  Skin('Blue', 30, Color(0xFFF0F6FF), Color(0xFFBFD7FF), Color(0xFF8FB2F0)),
  Skin('Mint', 50, Color(0xFFF2FFF9), Color(0xFFBFF2DE), Color(0xFF8FD6BC)),
];
const accNames = ['None', 'Bow', 'Nightcap', 'Glasses', 'Crown'];
const accCosts = [0, 20, 30, 25, 60];
const accEmoji = ['✨', '🎀', '🛏️', '👓', '👑'];

// ───────────────────────── entry points ─────────────────────────
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Color(0xFF12163F),
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  await Notifs.init();
  final state = AppState();
  await state.load();
  runApp(MoonApp(state));
}

/// Entry point for the floating bubble that is drawn over other apps.
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Material(color: Colors.transparent, child: OverlayBubble()),
  ));
}

// ───────────────────────── notifications ─────────────────────────
class Notifs {
  static final _np = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  static Future<void> init() async {
    try {
      tzdata.initializeTimeZones();
      await _np.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _ready = true;
    } catch (_) {}
  }

  static AndroidFlutterLocalNotificationsPlugin? get _android => _np
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  static Future<bool> askPermission() async {
    try {
      return await _android?.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<AndroidScheduleMode> _mode() async {
    try {
      final ok = await _android?.canScheduleExactNotifications() ?? false;
      return ok
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle;
    } catch (_) {
      return AndroidScheduleMode.inexactAllowWhileIdle;
    }
  }

  static tz.TZDateTime _at(int ms) =>
      tz.TZDateTime.fromMillisecondsSinceEpoch(tz.UTC, ms);

  /// Ongoing countdown notification + a scheduled alert for when it ends.
  static Future<void> timerStarted(int endAt, Phase p, String? task) async {
    if (!_ready) return;
    try {
      final focus = p == Phase.focus;
      await _np.show(
        id: 1,
        title: focus ? 'Focusing 🌙' : 'Break time 💤',
        body: focus ? (task ?? 'Luna is cheering you on ✨') : 'Rest your eyes ✨',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            'moonpomo_timer',
            'Running timer',
            channelDescription: 'Shows the countdown while a session runs',
            importance: Importance.low,
            priority: Priority.low,
            ongoing: true,
            autoCancel: false,
            onlyAlertOnce: true,
            showWhen: true,
            when: endAt,
            usesChronometer: true,
            chronometerCountDown: true,
            playSound: false,
            enableVibration: false,
          ),
        ),
      );
      await _np.zonedSchedule(
        id: 2,
        title: focus ? 'Session complete! 🍅' : 'Break over ☀️',
        body: focus
            ? 'Nice focus — Luna is proud of you. Time for a break.'
            : 'Ready for another focus session?',
        scheduledDate: _at(endAt),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'moonpomo_alerts',
            'Session alerts',
            channelDescription: 'Tells you when a session or break ends',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: await _mode(),
      );
    } catch (_) {}
  }

  static Future<void> cancelTimer() async {
    if (!_ready) return;
    try {
      await _np.cancel(id: 1);
      await _np.cancel(id: 2);
    } catch (_) {}
  }

  static Future<void> cancelOngoing() async {
    if (!_ready) return;
    try {
      await _np.cancel(id: 1);
    } catch (_) {}
  }

  static Future<void> cancelAll() async {
    if (!_ready) return;
    try {
      await _np.cancel(id: 1);
      await _np.cancel(id: 2);
      await _np.cancel(id: 3);
    } catch (_) {}
  }

  /// "Luna is hungry" reminder, kept out of the night hours.
  static Future<void> scheduleHungry(int? atMs, String name) async {
    if (!_ready) return;
    try {
      await _np.cancel(id: 3);
      if (atMs == null) return;
      var d = DateTime.fromMillisecondsSinceEpoch(atMs);
      if (d.hour >= 22 || d.hour < 8) {
        final base = d.hour >= 22 ? d.add(const Duration(days: 1)) : d;
        d = DateTime(base.year, base.month, base.day, 8);
      }
      if (d.millisecondsSinceEpoch < _now() + 60000) return;
      await _np.zonedSchedule(
        id: 3,
        title: '$name is hungry 🍬',
        body: 'Spend some stardust on a snack, or do a focus session to earn more.',
        scheduledDate: _at(d.millisecondsSinceEpoch),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'moonpomo_pet',
            'Moon care',
            channelDescription: 'Reminders when your moon needs a snack',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        androidScheduleMode: await _mode(),
      );
    } catch (_) {}
  }
}

// ───────────────────────── state ─────────────────────────
enum Phase { focus, short, long }

enum Mood { happy, focus, sleepy, sad, love }

class Task {
  Task(this.id, this.title, {this.done = false, this.pomos = 0, this.est = 2});
  final String id;
  String title;
  bool done;
  int pomos, est;
  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'done': done, 'pomos': pomos, 'est': est};
  factory Task.fromJson(Map<String, dynamic> j) => Task(
        j['id'] as String,
        j['title'] as String,
        done: j['done'] as bool? ?? false,
        pomos: j['pomos'] as int? ?? 0,
        est: j['est'] as int? ?? 2,
      );
}

String _key(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _today() => _key(DateTime.now());
int _now() => DateTime.now().millisecondsSinceEpoch;

class AppState extends ChangeNotifier {
  SharedPreferences? _p;
  final List<Task> tasks = [];
  int stardust = 10, xp = 0, cycle = 0, totalPomos = 0, totalMin = 0;
  final Map<String, int> history = {};
  double _fullness = 0.7;
  int _fedAt = _now();
  String? activeId;
  String petName = 'Luna';
  int skin = 0, acc = 0;
  Set<int> ownedSkins = {0}, ownedAcc = {0};

  // settings
  int focusMin = 25, shortMin = 5, longMin = 15, longEvery = 4;
  bool autoStart = false, vibrate = true, overlayOn = false, notify = true;

  // timer
  Phase phase = Phase.focus;
  bool running = false;
  int _endAt = 0;
  int remaining = 25 * 60;
  Timer? _t;
  int _lastLeft = -1;
  String? event; // one-shot toast message
  bool overlayShown = false;
  StreamSubscription<dynamic>? _ovSub;

  int dur(Phase p) =>
      (p == Phase.focus ? focusMin : (p == Phase.short ? shortMin : longMin)) * 60;

  int get left =>
      running ? math.max(0, ((_endAt - _now()) / 1000).ceil()) : remaining;
  double get progress => 1 - left / dur(phase);
  int get level => xp ~/ 50 + 1;
  double get levelProgress => (xp % 50) / 50;
  int get pomosToday => history[_today()] ?? 0;
  double get fullness =>
      (_fullness - (_now() - _fedAt) / 3600000 * 0.05).clamp(0.0, 1.0);

  int get streak {
    var d = DateTime.now();
    if ((history[_key(d)] ?? 0) == 0) d = d.subtract(const Duration(days: 1));
    var n = 0;
    while ((history[_key(d)] ?? 0) > 0) {
      n++;
      d = d.subtract(const Duration(days: 1));
    }
    return n;
  }

  List<int> get last7 {
    final now = DateTime.now();
    return [
      for (int i = 6; i >= 0; i--)
        history[_key(now.subtract(Duration(days: i)))] ?? 0
    ];
  }

  Task? get activeTask {
    for (final t in tasks) {
      if (t.id == activeId) return t;
    }
    return null;
  }

  Mood get mood {
    if (running && phase == Phase.focus) return Mood.focus;
    if (running) return Mood.sleepy;
    if (fullness < 0.25) return Mood.sad;
    return Mood.happy;
  }

  String get speech {
    final i = DateTime.now().minute ~/ 2;
    String pick(List<String> l) => l[i % l.length];
    if (running && phase == Phase.focus) {
      return pick(["Shh… we're focusing ✨", 'You got this! 💪', 'One tiny step at a time 🌱', "I'm guarding the stars for you ⭐"]);
    }
    if (running) return pick(['Ahh, cozy break~ 💤', 'Stretch your arms! 🙆', 'Sip some water 💧']);
    if (fullness < 0.25) return 'Tummy rumbly… star candy? 🍬';
    if (phase != Phase.focus) return 'Break time! Press play to rest.';
    return pick(['Ready when you are! 🌙', "Let's make tonight count ✨", 'Pick a task and tap play 🍅']);
  }

  // ── persistence
  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    final raw = _p!.getString('s2');
    if (raw != null) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        tasks
          ..clear()
          ..addAll((m['tasks'] as List? ?? [])
              .map((e) => Task.fromJson(Map<String, dynamic>.from(e as Map))));
        stardust = m['stardust'] as int? ?? stardust;
        xp = m['xp'] as int? ?? 0;
        cycle = m['cycle'] as int? ?? 0;
        totalPomos = m['totalPomos'] as int? ?? 0;
        totalMin = m['totalMin'] as int? ?? 0;
        history
          ..clear()
          ..addAll((m['history'] as Map? ?? {})
              .map((k, v) => MapEntry(k as String, v as int)));
        _fullness = (m['fullness'] as num? ?? 0.7).toDouble();
        _fedAt = m['fedAt'] as int? ?? _now();
        activeId = m['activeId'] as String?;
        petName = m['petName'] as String? ?? 'Luna';
        skin = m['skin'] as int? ?? 0;
        acc = m['acc'] as int? ?? 0;
        ownedSkins = Set<int>.from((m['ownedSkins'] as List? ?? [0]).cast<int>());
        ownedAcc = Set<int>.from((m['ownedAcc'] as List? ?? [0]).cast<int>());
        focusMin = m['focusMin'] as int? ?? 25;
        shortMin = m['shortMin'] as int? ?? 5;
        longMin = m['longMin'] as int? ?? 15;
        longEvery = m['longEvery'] as int? ?? 4;
        autoStart = m['autoStart'] as bool? ?? false;
        vibrate = m['vibrate'] as bool? ?? true;
        overlayOn = m['overlayOn'] as bool? ?? false;
        notify = m['notify'] as bool? ?? true;
        phase = Phase.values[(m['phase'] as int? ?? 0).clamp(0, 2)];
        remaining = m['remaining'] as int? ?? dur(phase);
        running = m['running'] as bool? ?? false;
        _endAt = m['endAt'] as int? ?? 0;
      } catch (_) {}
    } else {
      remaining = dur(phase);
    }
    if (running) {
      if (_endAt <= _now()) {
        _finish(); // finished while the app was closed
      } else {
        _startTicker();
      }
    }
    _planHungry();
  }

  void _save() {
    final cutoff = _key(DateTime.now().subtract(const Duration(days: 60)));
    history.removeWhere((k, _) => k.compareTo(cutoff) < 0);
    _p?.setString(
        's2',
        jsonEncode({
          'tasks': tasks.map((t) => t.toJson()).toList(),
          'stardust': stardust,
          'xp': xp,
          'cycle': cycle,
          'totalPomos': totalPomos,
          'totalMin': totalMin,
          'history': history,
          'fullness': _fullness,
          'fedAt': _fedAt,
          'activeId': activeId,
          'petName': petName,
          'skin': skin,
          'acc': acc,
          'ownedSkins': ownedSkins.toList(),
          'ownedAcc': ownedAcc.toList(),
          'focusMin': focusMin,
          'shortMin': shortMin,
          'longMin': longMin,
          'longEvery': longEvery,
          'autoStart': autoStart,
          'vibrate': vibrate,
          'overlayOn': overlayOn,
          'notify': notify,
          'phase': phase.index,
          'remaining': remaining,
          'running': running,
          'endAt': _endAt,
        }));
  }

  // ── timer
  void setPhase(Phase p) {
    if (running) return;
    phase = p;
    remaining = dur(p);
    _save();
    notifyListeners();
  }

  void _startTicker() {
    _t?.cancel();
    _lastLeft = -1;
    _t = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
  }

  void toggle() {
    HapticFeedback.mediumImpact();
    if (running) {
      remaining = left;
      running = false;
      _t?.cancel();
      Notifs.cancelTimer();
    } else {
      running = true;
      _endAt = _now() + remaining * 1000;
      _startTicker();
      if (notify) Notifs.timerStarted(_endAt, phase, activeTask?.title);
    }
    _save();
    notifyListeners();
  }

  void reset() {
    _t?.cancel();
    running = false;
    remaining = dur(phase);
    Notifs.cancelTimer();
    _save();
    notifyListeners();
  }

  void skip() {
    _t?.cancel();
    running = false;
    Notifs.cancelTimer();
    _advance();
    _save();
    notifyListeners();
  }

  void _tick() {
    final l = left;
    if (l <= 0) {
      _finish();
    } else if (l != _lastLeft) {
      _lastLeft = l;
      notifyListeners();
    }
  }

  Future<void> _buzz() async {
    if (!vibrate) return;
    for (var i = 0; i < 3; i++) {
      await HapticFeedback.heavyImpact();
      await Future<void>.delayed(const Duration(milliseconds: 260));
    }
  }

  void _finish() {
    _t?.cancel();
    running = false;
    Notifs.cancelOngoing();
    _buzz();
    if (phase == Phase.focus) {
      _snapFullness();
      final before = level;
      xp += 10;
      stardust += 5;
      final k = _today();
      history[k] = (history[k] ?? 0) + 1;
      totalPomos++;
      totalMin += focusMin;
      activeTask?.pomos++;
      event = level > before
          ? '🌙 Level up! $petName is now Lv $level'
          : '+10 xp  +5 ✨  — nice focus! Break time.';
    } else {
      event = 'Break over — ready to focus?';
    }
    _advance();
    _planHungry();
    _save();
    notifyListeners();
    if (autoStart) toggle();
  }

  void _advance() {
    if (phase == Phase.focus) {
      cycle++;
      phase = cycle % longEvery == 0 ? Phase.long : Phase.short;
    } else {
      phase = Phase.focus;
    }
    remaining = dur(phase);
  }

  /// Called when the app comes back to the foreground.
  void onResume() {
    closeBubble();
    if (running) {
      if (left <= 0) {
        _finish();
      } else {
        _startTicker();
      }
    }
    _planHungry();
    notifyListeners();
  }

  // ── settings
  void setDurations({int? f, int? s, int? l, int? every}) {
    focusMin = f ?? focusMin;
    shortMin = s ?? shortMin;
    longMin = l ?? longMin;
    longEvery = every ?? longEvery;
    if (!running) remaining = dur(phase);
    _save();
    notifyListeners();
  }

  void setFlags({bool? auto, bool? vib}) {
    autoStart = auto ?? autoStart;
    vibrate = vib ?? vibrate;
    _save();
    notifyListeners();
  }

  Future<void> setNotify(bool v) async {
    if (v) {
      await Notifs.askPermission();
      notify = true;
      _planHungry();
    } else {
      notify = false;
      await Notifs.cancelAll();
    }
    _save();
    notifyListeners();
  }

  Future<bool> setOverlay(bool v) async {
    if (!v) {
      overlayOn = false;
      await closeBubble();
      _save();
      notifyListeners();
      return true;
    }
    try {
      var granted = await FlutterOverlayWindow.isPermissionGranted();
      if (!granted) {
        granted = (await FlutterOverlayWindow.requestPermission()) ?? false;
      }
      overlayOn = granted;
    } catch (_) {
      overlayOn = false;
    }
    _save();
    notifyListeners();
    return overlayOn;
  }

  // ── floating bubble
  void attachOverlayListener() {
    try {
      _ovSub = FlutterOverlayWindow.overlayListener.listen((dynamic e) {
        if (e == 'toggle') toggle();
      });
    } catch (_) {}
  }

  Future<void> showBubble() async {
    if (!overlayOn || overlayShown) return;
    try {
      if (!await FlutterOverlayWindow.isPermissionGranted()) return;
      await FlutterOverlayWindow.showOverlay(
        height: 190,
        width: 140,
        alignment: OverlayAlignment.centerRight,
        enableDrag: true,
        flag: OverlayFlag.defaultFlag,
        positionGravity: PositionGravity.auto,
        overlayTitle: 'MoonPomo',
        overlayContent: '$petName is floating nearby',
      );
      overlayShown = true;
      Future<void>.delayed(const Duration(milliseconds: 600), _push);
    } catch (_) {}
  }

  Future<void> closeBubble() async {
    if (!overlayShown) return;
    overlayShown = false;
    try {
      await FlutterOverlayWindow.closeOverlay();
    } catch (_) {}
  }

  void _push() {
    if (!overlayShown) return;
    final m = {
      'mood': mood.index,
      'left': left,
      'running': running,
      'phase': phase.index,
      'level': level,
      'skin': skin,
      'acc': acc,
    };
    () async {
      try {
        await FlutterOverlayWindow.shareData(m);
      } catch (_) {}
    }();
  }

  @override
  void notifyListeners() {
    super.notifyListeners();
    _push();
  }

  // ── pet
  void _snapFullness() {
    _fullness = fullness;
    _fedAt = _now();
  }

  void _planHungry() {
    if (!notify) return;
    final hours = (fullness - 0.25) / 0.05;
    Notifs.scheduleHungry(
        hours > 0 ? _now() + (hours * 3600000).round() : null, petName);
  }

  bool feed(int cost, double amount) {
    if (stardust < cost) return false;
    _snapFullness();
    _fullness = math.min(1.0, _fullness + amount);
    stardust -= cost;
    xp += 2;
    HapticFeedback.lightImpact();
    _planHungry();
    _save();
    notifyListeners();
    return true;
  }

  void rename(String n) {
    if (n.trim().isEmpty) return;
    petName = n.trim();
    _save();
    notifyListeners();
  }

  /// returns 'equipped', 'bought' or 'poor'
  String pickSkin(int i) {
    if (!ownedSkins.contains(i)) {
      if (stardust < skins[i].cost) return 'poor';
      stardust -= skins[i].cost;
      ownedSkins.add(i);
      skin = i;
      _afterShop();
      return 'bought';
    }
    skin = i;
    _afterShop();
    return 'equipped';
  }

  String pickAcc(int i) {
    if (!ownedAcc.contains(i)) {
      if (stardust < accCosts[i]) return 'poor';
      stardust -= accCosts[i];
      ownedAcc.add(i);
      acc = i;
      _afterShop();
      return 'bought';
    }
    acc = i;
    _afterShop();
    return 'equipped';
  }

  void _afterShop() {
    HapticFeedback.selectionClick();
    _save();
    notifyListeners();
  }

  // ── tasks
  void addTask(String title, int est) {
    if (title.trim().isEmpty) return;
    final t = Task(DateTime.now().microsecondsSinceEpoch.toString(), title.trim(), est: est);
    tasks.add(t);
    activeId ??= t.id;
    _save();
    notifyListeners();
  }

  void toggleTask(String id) {
    final t = tasks.firstWhere((e) => e.id == id);
    t.done = !t.done;
    if (t.done) {
      stardust += 3;
      HapticFeedback.selectionClick();
      if (activeId == id) activeId = null;
    }
    _save();
    notifyListeners();
  }

  void setActive(String id) {
    activeId = activeId == id ? null : id;
    _save();
    notifyListeners();
  }

  void removeTask(String id) {
    tasks.removeWhere((e) => e.id == id);
    if (activeId == id) activeId = null;
    _save();
    notifyListeners();
  }

  void clearDone() {
    tasks.removeWhere((e) => e.done);
    _save();
    notifyListeners();
  }

  @override
  void dispose() {
    _t?.cancel();
    _ovSub?.cancel();
    super.dispose();
  }
}

// ───────────────────────── app shell ─────────────────────────
class MoonApp extends StatelessWidget {
  const MoonApp(this.state, {super.key});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MoonPomo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
            seedColor: kLilac, brightness: Brightness.dark, primary: kLilac),
        scaffoldBackgroundColor: Colors.transparent,
      ),
      home: HomeShell(state),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell(this.s, {super.key});
  final AppState s;
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.s.addListener(_onState);
    widget.s.attachOverlayListener();
    WidgetsBinding.instance.addPostFrameCallback((_) => _onState());
    // ask for notification permission once, softly
    Notifs.askPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.s.removeListener(_onState);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState st) {
    if (st == AppLifecycleState.resumed) {
      widget.s.onResume();
    } else if (st == AppLifecycleState.paused) {
      widget.s.showBubble();
    }
  }

  void _onState() {
    final e = widget.s.event;
    if (e == null || !mounted) return;
    widget.s.event = null;
    toast(context, e);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return Stack(children: [
      const Positioned.fill(child: Sky()),
      Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: IndexedStack(index: _tab, children: [
            FocusTab(s, onPlan: () => setState(() => _tab = 1)),
            PlanTab(s),
            MoonTab(s),
          ]),
        ),
        bottomNavigationBar: NavigationBar(
          backgroundColor: const Color(0xE612163F),
          indicatorColor: kLilac.withAlpha(60),
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.hourglass_empty_rounded),
                selectedIcon: Icon(Icons.hourglass_bottom_rounded),
                label: 'Focus'),
            NavigationDestination(
                icon: Icon(Icons.checklist_rounded), label: 'Plan'),
            NavigationDestination(
                icon: Icon(Icons.nightlight_outlined),
                selectedIcon: Icon(Icons.nightlight_round),
                label: 'Moon'),
          ],
        ),
      ),
    ]);
  }
}

void toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontWeight: FontWeight.w600)),
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF2B2670),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ));
}

// ───────────────────────── focus tab ─────────────────────────
class FocusTab extends StatelessWidget {
  const FocusTab(this.s, {super.key, required this.onPlan});
  final AppState s;
  final VoidCallback onPlan;

  String _fmt(int sec) =>
      '${(sec ~/ 60).toString().padLeft(2, '0')}:${(sec % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final brk = s.phase != Phase.focus;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 12, 24),
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(children: [
              Row(children: [
                Pill('🌙', 'Lv ${s.level}'),
                const SizedBox(width: 8),
                Pill('✨', '${s.stardust}'),
                const SizedBox(width: 8),
                Pill('🍅', '${s.pomosToday}'),
                const Spacer(),
                IconButton(
                  tooltip: 'Settings',
                  onPressed: () => showSettings(context, s),
                  icon: const Icon(Icons.tune_rounded),
                ),
              ]),
              const SizedBox(height: 8),
              _PhaseSelector(s),
              const SizedBox(height: 10),
              SizedBox(
                width: 300,
                height: 320,
                child: Stack(alignment: Alignment.center, children: [
                  Positioned.fill(
                      child: CustomPaint(painter: RingPainter(s.progress, brk))),
                  Align(
                    alignment: const Alignment(0, -0.22),
                    child: MoonPet(
                        mood: s.mood, level: s.level, skin: s.skin, acc: s.acc, size: 210),
                  ),
                  Align(
                    alignment: const Alignment(0, 0.66),
                    child: Text(_fmt(s.left),
                        style: const TextStyle(
                          fontSize: 46,
                          fontWeight: FontWeight.w300,
                          letterSpacing: 2,
                          fontFeatures: [FontFeature.tabularFigures()],
                        )),
                  ),
                ]),
              ),
              const SizedBox(height: 4),
              Glass(
                radius: 20,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Text(s.speech,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 15, color: Colors.white70)),
              ),
              const SizedBox(height: 14),
              GestureDetector(
                onTap: onPlan,
                child: Pill('🎯',
                    s.activeTask == null ? 'Pick a task in Plan' : s.activeTask!.title),
              ),
              const SizedBox(height: 22),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(
                    iconSize: 30,
                    onPressed: s.reset,
                    icon: const Icon(Icons.restart_alt_rounded)),
                const SizedBox(width: 22),
                GestureDetector(
                  onTap: s.toggle,
                  child: Container(
                    width: 82,
                    height: 82,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                          colors: [kGold, kPink],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight),
                      boxShadow: [
                        BoxShadow(
                            color: kPink.withAlpha(90), blurRadius: 24, spreadRadius: 1)
                      ],
                    ),
                    child: Icon(
                        s.running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        size: 46,
                        color: kInk),
                  ),
                ),
                const SizedBox(width: 22),
                IconButton(
                    iconSize: 30,
                    onPressed: s.skip,
                    icon: const Icon(Icons.skip_next_rounded)),
              ]),
            ]),
          ),
        );
      },
    );
  }
}

class _PhaseSelector extends StatelessWidget {
  const _PhaseSelector(this.s);
  final AppState s;
  @override
  Widget build(BuildContext context) {
    const labels = {Phase.focus: 'Focus', Phase.short: 'Short', Phase.long: 'Long'};
    return Glass(
      radius: 30,
      padding: const EdgeInsets.all(4),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final p in Phase.values)
          GestureDetector(
            onTap: () => s.setPhase(p),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
              decoration: BoxDecoration(
                color: s.phase == p ? kLilac.withAlpha(70) : Colors.transparent,
                borderRadius: BorderRadius.circular(26),
              ),
              child: Text(labels[p]!,
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: s.phase == p ? Colors.white : Colors.white54)),
            ),
          ),
      ]),
    );
  }
}

// ───────────────────────── settings ─────────────────────────
void showSettings(BuildContext context, AppState s) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF1B1950),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    builder: (_) => SettingsSheet(s),
  );
}

class SettingsSheet extends StatelessWidget {
  const SettingsSheet(this.s, {super.key});
  final AppState s;

  Widget _slider(String label, int v, int min, int max, int step, void Function(int) on) {
    return Column(children: [
      Row(children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const Spacer(),
        Text('$v', style: const TextStyle(color: kGold, fontWeight: FontWeight.w700)),
      ]),
      Slider(
        value: v.toDouble(),
        min: min.toDouble(),
        max: max.toDouble(),
        divisions: (max - min) ~/ step,
        onChanged: (x) => on(x.round()),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(22, 14, 22, 22 + MediaQuery.of(context).viewInsets.bottom),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(
            child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24, borderRadius: BorderRadius.circular(4))),
          ),
          const SizedBox(height: 14),
          const Text('Settings', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          _slider('Focus (min)', s.focusMin, 5, 60, 5, (v) => s.setDurations(f: v)),
          _slider('Short break (min)', s.shortMin, 1, 15, 1, (v) => s.setDurations(s: v)),
          _slider('Long break (min)', s.longMin, 5, 30, 5, (v) => s.setDurations(l: v)),
          _slider('Long break every N sessions', s.longEvery, 2, 8, 1, (v) => s.setDurations(every: v)),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Auto-start next session'),
            value: s.autoStart,
            onChanged: (v) => s.setFlags(auto: v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Vibrate when a session ends'),
            value: s.vibrate,
            onChanged: (v) => s.setFlags(vib: v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Notifications'),
            subtitle: const Text('Live countdown, session alerts, hungry moon'),
            value: s.notify,
            onChanged: (v) => s.setNotify(v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Floating moon over other apps'),
            subtitle: const Text('Shows when you leave the app. Tap the time to pause/resume.'),
            value: s.overlayOn,
            onChanged: (v) async {
              final ok = await s.setOverlay(v);
              if (v && !ok && context.mounted) {
                toast(context, 'Allow "Display over other apps" for MoonPomo, then switch this on again.');
              }
            },
          ),
        ]),
      ),
    );
  }
}

// ───────────────────────── plan tab ─────────────────────────
class PlanTab extends StatefulWidget {
  const PlanTab(this.s, {super.key});
  final AppState s;
  @override
  State<PlanTab> createState() => _PlanTabState();
}

class _PlanTabState extends State<PlanTab> {
  final _c = TextEditingController();
  int _est = 2;

  void _add() {
    widget.s.addTask(_c.text, _est);
    _c.clear();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.s;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final list = [
          ...s.tasks.where((t) => !t.done),
          ...s.tasks.where((t) => t.done),
        ];
        final doneCount = s.tasks.where((t) => t.done).length;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Expanded(
                child: Text("Tonight's plan",
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
              ),
              if (doneCount > 0)
                TextButton(onPressed: s.clearDone, child: const Text('Clear done')),
            ]),
            const SizedBox(height: 4),
            Text('${s.tasks.length - doneCount} to go  ·  tap 🎯 to focus on a task  ·  swipe to delete',
                style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 16),
            Glass(
              radius: 22,
              padding: const EdgeInsets.only(left: 16, right: 6),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _c,
                    onSubmitted: (_) => _add(),
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                        hintText: 'Add a wish for tonight…', border: InputBorder.none),
                  ),
                ),
                IconButton.filled(
                  style: IconButton.styleFrom(backgroundColor: kLilac, foregroundColor: kInk),
                  onPressed: _add,
                  icon: const Icon(Icons.add_rounded),
                ),
              ]),
            ),
            const SizedBox(height: 8),
            Row(children: [
              const Text('Estimate', style: TextStyle(color: Colors.white54)),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: _est > 1 ? () => setState(() => _est--) : null,
                icon: const Icon(Icons.remove_circle_outline_rounded),
              ),
              Text('🍅 × $_est', style: const TextStyle(fontWeight: FontWeight.w700)),
              IconButton(
                visualDensity: VisualDensity.compact,
                onPressed: _est < 12 ? () => setState(() => _est++) : null,
                icon: const Icon(Icons.add_circle_outline_rounded),
              ),
            ]),
            Expanded(
              child: list.isEmpty
                  ? const Center(
                      child: Text('Nothing planned yet ✨\nAdd your first task above.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white38, height: 1.5)))
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: list.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _taskTile(s, list[i]),
                    ),
            ),
          ]),
        );
      },
    );
  }

  Widget _taskTile(AppState s, Task t) {
    final active = s.activeId == t.id;
    return Dismissible(
      key: ValueKey(t.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => s.removeTask(t.id),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
            color: Colors.redAccent.withAlpha(70), borderRadius: BorderRadius.circular(22)),
        child: const Icon(Icons.delete_outline_rounded),
      ),
      child: Glass(
        radius: 22,
        border: active ? kGold.withAlpha(160) : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(children: [
          GestureDetector(
            onTap: () => s.toggleTask(t.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.done ? kMint : Colors.transparent,
                border: Border.all(color: t.done ? kMint : Colors.white38, width: 2),
              ),
              child: t.done ? const Icon(Icons.check_rounded, size: 18, color: kInk) : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(t.title,
                style: TextStyle(
                  fontSize: 16,
                  color: t.done ? Colors.white38 : Colors.white,
                  decoration: t.done ? TextDecoration.lineThrough : null,
                )),
          ),
          Text('🍅 ${t.pomos}/${t.est}  ',
              style: TextStyle(
                  fontSize: 13,
                  color: t.pomos >= t.est ? kMint : Colors.white70,
                  fontWeight: FontWeight.w600)),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: t.done ? null : () => s.setActive(t.id),
            icon: Icon(active ? Icons.my_location_rounded : Icons.adjust_rounded,
                color: active ? kGold : Colors.white38),
          ),
        ]),
      ),
    );
  }
}

// ───────────────────────── moon tab ─────────────────────────
class MoonTab extends StatelessWidget {
  const MoonTab(this.s, {super.key});
  final AppState s;

  Future<void> _rename(BuildContext context) async {
    final c = TextEditingController(text: s.petName);
    final n = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF241F5E),
        title: const Text('Name your moon'),
        content: TextField(controller: c, autofocus: true, maxLength: 14),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('Save')),
        ],
      ),
    );
    c.dispose();
    if (n != null) s.rename(n);
  }

  void _feed(BuildContext context, int cost, double amt) {
    if (!s.feed(cost, amt)) toast(context, 'Not enough stardust — go focus to earn some ✨');
  }

  void _shop(BuildContext context, String r) {
    if (r == 'poor') toast(context, 'Not enough stardust yet ✨');
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final hours = (s.totalMin / 60);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(children: [
            Align(alignment: Alignment.centerRight, child: Pill('✨', '${s.stardust}')),
            MoonPet(mood: s.mood, level: s.level, skin: s.skin, acc: s.acc, size: 260),
            GestureDetector(
              onTap: () => _rename(context),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(s.petName,
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
                const SizedBox(width: 6),
                const Icon(Icons.edit_rounded, size: 16, color: Colors.white38),
              ]),
            ),
            const SizedBox(height: 4),
            Text('Level ${s.level}  ·  tap the moon to pet it',
                style: const TextStyle(color: Colors.white54)),
            const SizedBox(height: 20),
            Glass(
              radius: 24,
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                _Bar('Growth', '${s.xp % 50}/50 xp', s.levelProgress, kLilac),
                const SizedBox(height: 14),
                _Bar('Tummy', '${(s.fullness * 100).round()}%', s.fullness, kPink),
              ]),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _Feed('🍬', 'Star candy', 5, () => _feed(context, 5, 0.25))),
              const SizedBox(width: 12),
              Expanded(child: _Feed('☁️', 'Cloud milk', 10, () => _feed(context, 10, 0.55))),
            ]),
            const SizedBox(height: 18),
            _sectionTitle('This week'),
            Glass(
              radius: 24,
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(children: [
                SizedBox(
                  height: 110,
                  width: double.infinity,
                  child: CustomPaint(painter: WeekPainter(s.last7, DateTime.now())),
                ),
                const SizedBox(height: 10),
                Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                  _Stat('🔥', '${s.streak}', 'day streak'),
                  _Stat('🍅', '${s.totalPomos}', 'sessions'),
                  _Stat('⏱️', hours >= 10 ? hours.toStringAsFixed(0) : hours.toStringAsFixed(1), 'hours focused'),
                ]),
              ]),
            ),
            const SizedBox(height: 18),
            _sectionTitle('Closet'),
            SizedBox(
              height: 92,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (int i = 0; i < skins.length; i++)
                  _Tile(
                    leading: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                            colors: [skins[i].hi, skins[i].lo],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight),
                      ),
                    ),
                    label: skins[i].name,
                    price: s.ownedSkins.contains(i) ? null : skins[i].cost,
                    selected: s.skin == i,
                    onTap: () => _shop(context, s.pickSkin(i)),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 92,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                for (int i = 0; i < accNames.length; i++)
                  _Tile(
                    leading: Text(accEmoji[i], style: const TextStyle(fontSize: 26)),
                    label: accNames[i],
                    price: s.ownedAcc.contains(i) ? null : accCosts[i],
                    selected: s.acc == i,
                    onTap: () => _shop(context, s.pickAcc(i)),
                  ),
              ]),
            ),
            const SizedBox(height: 16),
            const Text(
              'Finish a focus session → +10 xp, +5 ✨.\nKeep the tummy full or the moon gets sad.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white38, height: 1.5),
            ),
          ]),
        );
      },
    );
  }

  Widget _sectionTitle(String t) => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Text(t, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        ),
      );
}

class _Stat extends StatelessWidget {
  const _Stat(this.emoji, this.value, this.label);
  final String emoji, value, label;
  @override
  Widget build(BuildContext context) => Column(children: [
        Text('$emoji $value', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.white54)),
      ]);
}

class _Tile extends StatelessWidget {
  const _Tile({required this.leading, required this.label, required this.price, required this.selected, required this.onTap});
  final Widget leading;
  final String label;
  final int? price;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 84,
          child: Glass(
            radius: 20,
            border: selected ? kGold.withAlpha(200) : null,
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(height: 34, child: Center(child: leading)),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              Text(
                selected ? 'wearing' : (price == null ? 'owned' : '$price ✨'),
                style: TextStyle(fontSize: 11, color: selected ? kGold : (price == null ? Colors.white38 : kPink)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar(this.label, this.value, this.v, this.color);
  final String label, value;
  final double v;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Row(children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const Spacer(),
        Text(value, style: const TextStyle(color: Colors.white54)),
      ]),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: LinearProgressIndicator(
          value: v,
          minHeight: 10,
          color: color,
          backgroundColor: Colors.white.withAlpha(25),
        ),
      ),
    ]);
  }
}

class _Feed extends StatelessWidget {
  const _Feed(this.emoji, this.label, this.cost, this.onTap);
  final String emoji, label;
  final int cost;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Glass(
        radius: 22,
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(children: [
          Text(emoji, style: const TextStyle(fontSize: 34)),
          const SizedBox(height: 6),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text('$cost ✨', style: const TextStyle(color: kGold)),
        ]),
      ),
    );
  }
}

class WeekPainter extends CustomPainter {
  WeekPainter(this.v, this.today);
  final List<int> v;
  final DateTime today;
  @override
  void paint(Canvas canvas, Size size) {
    const labels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final maxV = math.max(4, v.reduce(math.max));
    final slot = size.width / 7;
    final chartH = size.height - 20;
    for (int i = 0; i < 7; i++) {
      final date = today.subtract(Duration(days: 6 - i));
      final h = v[i] / maxV * (chartH - 16);
      final x = slot * i + slot / 2;
      final isToday = i == 6;
      final bar = RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 9, chartH - math.max(h, 4), 18, math.max(h, 4)), const Radius.circular(9));
      canvas.drawRRect(
          bar,
          Paint()
            ..color = v[i] == 0
                ? Colors.white.withAlpha(25)
                : (isToday ? kGold : kLilac));
      _t(canvas, labels[date.weekday - 1], Offset(x, size.height - 8), 11,
          isToday ? Colors.white : Colors.white54, FontWeight.w600);
      if (v[i] > 0) {
        _t(canvas, '${v[i]}', Offset(x, chartH - h - 10), 11, Colors.white70, FontWeight.w700);
      }
    }
  }

  void _t(Canvas c, String s, Offset center, double size, Color col, FontWeight w) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: col, fontSize: size, fontWeight: w)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(WeekPainter o) => true;
}

// ───────────────────────── small widgets ─────────────────────────
class Glass extends StatelessWidget {
  const Glass({super.key, required this.child, this.padding, this.radius = 24, this.border});
  final Widget child;
  final EdgeInsets? padding;
  final double radius;
  final Color? border;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(20),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
            color: border ?? Colors.white.withAlpha(30), width: border != null ? 1.5 : 1),
      ),
      child: child,
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.emoji, this.label, {super.key});
  final String emoji, label;
  @override
  Widget build(BuildContext context) {
    return Glass(
      radius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(emoji),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
        ),
      ]),
    );
  }
}

// ───────────────────────── twinkling sky ─────────────────────────
class Sky extends StatefulWidget {
  const Sky({super.key});
  @override
  State<Sky> createState() => _SkyState();
}

class _SkyState extends State<Sky> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  static final List<_Star> _stars = () {
    final r = math.Random(7);
    return List.generate(
        70,
        (_) => _Star(r.nextDouble(), r.nextDouble(), 0.6 + r.nextDouble() * 1.6,
            r.nextDouble() * math.pi * 2, 1 + r.nextInt(3)));
  }();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [kBg0, kBg1, kBg2]),
      ),
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(painter: _SkyPainter(_c.value, _stars)),
      ),
    );
  }
}

class _Star {
  const _Star(this.x, this.y, this.r, this.phase, this.k);
  final double x, y, r, phase;
  final int k;
}

class _SkyPainter extends CustomPainter {
  _SkyPainter(this.t, this.stars);
  final double t;
  final List<_Star> stars;
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint();
    for (final s in stars) {
      final a = 0.3 + 0.7 * (0.5 + 0.5 * math.sin(t * 2 * math.pi * s.k + s.phase));
      p.color = Colors.white.withAlpha((a * 255).round());
      canvas.drawCircle(Offset(s.x * size.width, s.y * size.height), s.r, p);
    }
  }

  @override
  bool shouldRepaint(_SkyPainter old) => true;
}

// ───────────────────────── timer ring ─────────────────────────
class RingPainter extends CustomPainter {
  RingPainter(this.progress, this.brk);
  final double progress;
  final bool brk;
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final rad = math.min(size.width, size.height) / 2 - 8;
    final rect = Rect.fromCircle(center: c, radius: rad);
    canvas.drawCircle(
        c,
        rad,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..color = Colors.white.withAlpha(22));
    if (progress <= 0) return;
    final colors = brk ? [kMint, kLilac] : [kLilac, kGold];
    canvas.drawArc(
        rect,
        -math.pi / 2,
        2 * math.pi * progress,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..strokeCap = StrokeCap.round
          ..shader = SweepGradient(
            colors: colors,
            transform: const GradientRotation(-math.pi / 2),
          ).createShader(rect));
    final a = -math.pi / 2 + 2 * math.pi * progress;
    canvas.drawCircle(
        c + Offset(math.cos(a), math.sin(a)) * rad, 7, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(RingPainter o) => o.progress != progress || o.brk != brk;
}

// ───────────────────────── the moon pet ─────────────────────────
class MoonPet extends StatefulWidget {
  const MoonPet({
    super.key,
    required this.mood,
    required this.level,
    required this.size,
    this.skin = 0,
    this.acc = 0,
    this.onTap,
  });
  final Mood mood;
  final int level, skin, acc;
  final double size;
  final VoidCallback? onTap;
  @override
  State<MoonPet> createState() => _MoonPetState();
}

class _MoonPetState extends State<MoonPet> with TickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();
  late final AnimationController _pop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));
  bool _blink = false;
  Timer? _bt, _bt2;
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _scheduleBlink();
  }

  void _scheduleBlink() {
    _bt = Timer(Duration(milliseconds: 2200 + _rng.nextInt(2800)), () {
      if (!mounted) return;
      setState(() => _blink = true);
      _bt2 = Timer(const Duration(milliseconds: 130), () {
        if (!mounted) return;
        setState(() => _blink = false);
        _scheduleBlink();
      });
    });
  }

  @override
  void dispose() {
    _bt?.cancel();
    _bt2?.cancel();
    _c.dispose();
    _pop.dispose();
    super.dispose();
  }

  void _pet() {
    HapticFeedback.lightImpact();
    _pop.forward(from: 0);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    return GestureDetector(
      onTap: _pet,
      child: SizedBox(
        width: size,
        height: size,
        child: AnimatedBuilder(
          animation: Listenable.merge([_c, _pop]),
          builder: (_, __) {
            final love = _pop.isAnimating;
            final p = _pop.value;
            final squish = love ? 1 + 0.07 * math.sin(p * math.pi * 4) * (1 - p) : 1.0;
            return Stack(clipBehavior: Clip.none, children: [
              Transform.scale(
                scale: squish,
                child: CustomPaint(
                  size: Size(size, size),
                  painter: MoonPainter(
                    mood: love ? Mood.love : widget.mood,
                    blink: _blink,
                    v: _c.value,
                    level: widget.level,
                    skin: widget.skin,
                    acc: widget.acc,
                  ),
                ),
              ),
              if (love)
                for (int i = 0; i < 3; i++)
                  Positioned(
                    left: size * (0.28 + 0.2 * i),
                    top: size * 0.22 - p * size * (0.22 + 0.06 * i),
                    child: Opacity(
                      opacity: (1 - p).clamp(0.0, 1.0),
                      child: Text('💗', style: TextStyle(fontSize: size * (0.075 + 0.02 * i))),
                    ),
                  ),
            ]);
          },
        ),
      ),
    );
  }
}

class MoonPainter extends CustomPainter {
  MoonPainter({
    required this.mood,
    required this.blink,
    required this.v,
    required this.level,
    this.skin = 0,
    this.acc = 0,
  });
  final Mood mood;
  final bool blink;
  final double v; // 0..1 over 12s
  final int level, skin, acc;

  Path _star(Offset c, double R) {
    final p = Path();
    for (int i = 0; i < 8; i++) {
      final rad = i.isEven ? R : R * 0.38;
      final a = -math.pi / 2 + i * math.pi / 4;
      final o = c + Offset(math.cos(a) * rad, math.sin(a) * rad);
      i == 0 ? p.moveTo(o.dx, o.dy) : p.lineTo(o.dx, o.dy);
    }
    return p..close();
  }

  void _text(Canvas canvas, String s, Offset o, double size, double alpha) {
    final tp = TextPainter(
      text: TextSpan(
          text: s,
          style: TextStyle(
              color: Colors.white.withAlpha((alpha * 255).round()),
              fontSize: size,
              fontWeight: FontWeight.w700)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, o);
  }

  void _accessory(Canvas canvas, Offset c, double r, double ey, double ex) {
    switch (acc) {
      case 1: // bow
        canvas.save();
        canvas.translate(c.dx - r * 0.56, c.dy - r * 0.8);
        canvas.rotate(-0.5);
        final wing = Paint()..color = const Color(0xFFFF7FAE);
        final l = Path()
          ..moveTo(0, 0)
          ..lineTo(-r * 0.3, -r * 0.17)
          ..lineTo(-r * 0.3, r * 0.17)
          ..close();
        final rr = Path()
          ..moveTo(0, 0)
          ..lineTo(r * 0.3, -r * 0.17)
          ..lineTo(r * 0.3, r * 0.17)
          ..close();
        canvas.drawPath(l, wing);
        canvas.drawPath(rr, wing);
        canvas.drawCircle(Offset.zero, r * 0.075, Paint()..color = const Color(0xFFFFB3CF));
        canvas.restore();
        break;
      case 2: // nightcap
        final a1 = -150 * math.pi / 180, a2 = -30 * math.pi / 180;
        final p1 = c + Offset(math.cos(a1), math.sin(a1)) * r;
        final p2 = c + Offset(math.cos(a2), math.sin(a2)) * r;
        final tip = c + Offset(r * 0.42, -r * 1.42);
        final cap = Path()
          ..moveTo(p1.dx, p1.dy)
          ..quadraticBezierTo(c.dx - r * 0.7, c.dy - r * 1.35, tip.dx, tip.dy)
          ..quadraticBezierTo(c.dx + r * 0.6, c.dy - r * 0.95, p2.dx, p2.dy)
          ..close();
        canvas.drawPath(cap, Paint()..color = const Color(0xFF7C6BE0));
        canvas.drawArc(Rect.fromCircle(center: c, radius: r * 1.0), a1, a2 - a1, false,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = r * 0.14
              ..strokeCap = StrokeCap.round
              ..color = Colors.white);
        canvas.drawCircle(tip, r * 0.1, Paint()..color = Colors.white);
        break;
      case 3: // glasses
        final rim = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = r * 0.04
          ..color = kInk;
        final lens = Paint()..color = Colors.white.withAlpha(45);
        for (final sx in const [-1.0, 1.0]) {
          final e = Offset(c.dx + sx * ex, ey);
          canvas.drawCircle(e, r * 0.21, lens);
          canvas.drawCircle(e, r * 0.21, rim);
        }
        canvas.drawLine(Offset(c.dx - ex + r * 0.21, ey), Offset(c.dx + ex - r * 0.21, ey), rim);
        break;
      case 4: // crown
        final b = c.dy - r * 0.9;
        final x = c.dx;
        final crown = Path()
          ..moveTo(x - r * 0.4, b)
          ..lineTo(x - r * 0.4, b - r * 0.42)
          ..lineTo(x - r * 0.2, b - r * 0.22)
          ..lineTo(x, b - r * 0.5)
          ..lineTo(x + r * 0.2, b - r * 0.22)
          ..lineTo(x + r * 0.4, b - r * 0.42)
          ..lineTo(x + r * 0.4, b)
          ..close();
        canvas.drawPath(crown, Paint()..color = const Color(0xFFFFC93C));
        canvas.drawPath(
            crown,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = r * 0.03
              ..strokeJoin = StrokeJoin.round
              ..color = const Color(0xFFE0A030));
        for (final dx in const [-0.4, 0.0, 0.4]) {
          canvas.drawCircle(Offset(x + dx * r, b - r * (dx == 0 ? 0.5 : 0.42)), r * 0.05,
              Paint()..color = const Color(0xFFFF6B8B));
        }
        break;
    }
  }

  @override
  void paint(Canvas canvas, Size s) {
    final sk = skins[skin.clamp(0, skins.length - 1)];
    final h = math.sin(v * 2 * math.pi * 4); // hover, 3s period
    final r = s.width * 0.32;
    final c = Offset(s.width / 2, s.height * 0.46 + h * s.height * 0.022);

    // ground shadow
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(s.width / 2, s.height * 0.92),
          width: r * (1.5 - 0.18 * h),
          height: r * 0.26),
      Paint()
        ..color = kLilac.withAlpha(60)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // glow
    canvas.drawCircle(
      c,
      r * 1.9,
      Paint()
        ..shader = RadialGradient(colors: [sk.mid.withAlpha(85), sk.mid.withAlpha(0)])
            .createShader(Rect.fromCircle(center: c, radius: r * 1.9)),
    );

    // orbiting stars (one per level above 1, max 5)
    final n = math.min(level - 1, 5);
    for (int i = 0; i < n; i++) {
      final a = v * 2 * math.pi + i * 2 * math.pi / n;
      final o = c + Offset(math.cos(a) * r * 1.5, math.sin(a) * r * 0.5 - r * 0.15);
      canvas.drawPath(_star(o, r * 0.11), Paint()..color = const Color(0xFFFFF1B8));
    }

    // body
    final body = Rect.fromCircle(center: c, radius: r);
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.5),
          radius: 1.1,
          colors: [sk.hi, sk.mid, sk.lo],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(body),
    );

    // craters
    final cr = Paint()..color = sk.lo.withAlpha(55);
    for (final k in const [
      [-0.5, -0.62, 0.15],
      [0.58, -0.55, 0.1],
      [0.1, 0.78, 0.12],
      [-0.78, 0.3, 0.08],
      [0.78, 0.5, 0.08],
    ]) {
      canvas.drawCircle(c + Offset(k[0] * r, k[1] * r), k[2] * r, cr);
    }

    // face
    final ink = Paint()..color = kInk;
    final stroke = Paint()
      ..color = kInk
      ..style = PaintingStyle.stroke
      ..strokeWidth = r * 0.055
      ..strokeCap = StrokeCap.round;
    final ey = c.dy + r * 0.02;
    final ex = r * 0.4;
    final closedU = blink || mood == Mood.sleepy;
    final closedHat = mood == Mood.love;

    for (final sx in const [-1.0, 1.0]) {
      final e = Offset(c.dx + sx * ex, ey);
      if (closedHat) {
        canvas.drawArc(
            Rect.fromCenter(center: e + Offset(0, r * 0.03), width: r * 0.2, height: r * 0.14),
            math.pi, math.pi, false, stroke);
      } else if (closedU) {
        canvas.drawArc(
            Rect.fromCenter(center: e - Offset(0, r * 0.03), width: r * 0.2, height: r * 0.14),
            0, math.pi, false, stroke);
      } else {
        canvas.drawOval(Rect.fromCenter(center: e, width: r * 0.17, height: r * 0.25), ink);
        canvas.drawCircle(e + Offset(-r * 0.03, -r * 0.06), r * 0.035, Paint()..color = Colors.white);
      }
      if (!closedU && !closedHat && (mood == Mood.focus || mood == Mood.sad)) {
        final inner = mood == Mood.focus ? 0.13 : 0.2;
        final outer = mood == Mood.focus ? 0.2 : 0.13;
        canvas.drawLine(
          Offset(e.dx - sx * r * 0.11, ey - r * outer),
          Offset(e.dx + sx * r * 0.11, ey - r * inner),
          stroke,
        );
      }
    }

    // cheeks
    final cheek = Paint()..color = kPink.withAlpha(mood == Mood.love ? 170 : 110);
    for (final sx in const [-1.0, 1.0]) {
      canvas.drawOval(
          Rect.fromCenter(
              center: Offset(c.dx + sx * r * 0.63, ey + r * 0.2), width: r * 0.22, height: r * 0.13),
          cheek);
    }

    // mouth
    final m = Offset(c.dx, ey + r * 0.2);
    switch (mood) {
      case Mood.love:
        canvas.drawArc(Rect.fromCenter(center: m, width: r * 0.24, height: r * 0.22), 0, math.pi, true,
            Paint()..color = const Color(0xFFC2476B));
        break;
      case Mood.sleepy:
        canvas.drawOval(
            Rect.fromCenter(center: m + Offset(0, r * 0.03), width: r * 0.09, height: r * 0.11),
            Paint()..color = kInk.withAlpha(200));
        break;
      case Mood.sad:
        canvas.drawArc(Rect.fromCenter(center: m + Offset(0, r * 0.06), width: r * 0.18, height: r * 0.12),
            math.pi, math.pi, false, stroke);
        break;
      case Mood.focus:
        canvas.drawArc(Rect.fromCenter(center: m, width: r * 0.14, height: r * 0.09), 0, math.pi, false, stroke);
        break;
      case Mood.happy:
        canvas.drawArc(Rect.fromCenter(center: m, width: r * 0.2, height: r * 0.14), 0, math.pi, false, stroke);
        break;
    }

    _accessory(canvas, c, r, ey, ex);

    // floating zzz when sleepy
    if (mood == Mood.sleepy) {
      for (int i = 0; i < 2; i++) {
        final f = ((v * 4) + i * 0.5) % 1.0;
        _text(canvas, 'z', c + Offset(r * 0.75 + f * r * 0.4, -r * 0.55 - f * r * 0.6),
            r * (0.2 + 0.15 * f), 1 - f);
      }
    }
  }

  @override
  bool shouldRepaint(MoonPainter o) => true;
}

// ───────────────────────── floating bubble (runs in its own engine) ─────────────────────────
class OverlayBubble extends StatefulWidget {
  const OverlayBubble({super.key});
  @override
  State<OverlayBubble> createState() => _OverlayBubbleState();
}

class _OverlayBubbleState extends State<OverlayBubble> {
  Mood _mood = Mood.happy;
  int _left = 0, _level = 1, _skin = 0, _acc = 0, _phase = 0;
  bool _running = false;
  StreamSubscription<dynamic>? _sub;

  @override
  void initState() {
    super.initState();
    try {
      _sub = FlutterOverlayWindow.overlayListener.listen((dynamic e) {
        if (e is! Map || !mounted) return;
        setState(() {
          _mood = Mood.values[((e['mood'] as num?)?.toInt() ?? 0).clamp(0, 4)];
          _left = (e['left'] as num?)?.toInt() ?? 0;
          _level = (e['level'] as num?)?.toInt() ?? 1;
          _skin = (e['skin'] as num?)?.toInt() ?? 0;
          _acc = (e['acc'] as num?)?.toInt() ?? 0;
          _phase = (e['phase'] as num?)?.toInt() ?? 0;
          _running = e['running'] as bool? ?? false;
        });
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  String get _time =>
      '${(_left ~/ 60).toString().padLeft(2, '0')}:${(_left % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      MoonPet(mood: _mood, level: _level, skin: _skin, acc: _acc, size: 128),
      GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          () async {
            try {
              await FlutterOverlayWindow.shareData('toggle');
            } catch (_) {}
          }();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xE61C1B4B),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: (_phase == 0 ? kGold : kMint).withAlpha(140), width: 1.5),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(_running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 16, color: _phase == 0 ? kGold : kMint),
            const SizedBox(width: 4),
            Text(_time,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ]),
        ),
      ),
    ]);
  }
}
