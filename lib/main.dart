// MoonPomo — a cute moon tamagotchi that lives in your pomodoro planner.
// Single file. Needs: shared_preferences. Flutter 3.22+ / Dart 3.4+.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ───────────────────────── palette ─────────────────────────
const kBg0 = Color(0xFF0A0E2A);
const kBg1 = Color(0xFF1C1B4B);
const kBg2 = Color(0xFF3A2A6B);
const kGold = Color(0xFFFFD98A);
const kPink = Color(0xFFFF9EC4);
const kLilac = Color(0xFFB9A6FF);
const kMint = Color(0xFF8FE3CF);
const kInk = Color(0xFF3B2F5C);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Color(0xFF12163F),
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  final state = AppState();
  await state.load();
  runApp(MoonApp(state));
}

// ───────────────────────── state ─────────────────────────
enum Phase { focus, short, long }

enum Mood { happy, focus, sleepy, sad, love }

class Task {
  Task(this.id, this.title, {this.done = false, this.pomos = 0});
  final String id;
  String title;
  bool done;
  int pomos;
  Map<String, dynamic> toJson() =>
      {'id': id, 'title': title, 'done': done, 'pomos': pomos};
  factory Task.fromJson(Map<String, dynamic> j) => Task(
        j['id'] as String,
        j['title'] as String,
        done: j['done'] as bool? ?? false,
        pomos: j['pomos'] as int? ?? 0,
      );
}

String _today() {
  final d = DateTime.now();
  return '${d.year}-${d.month}-${d.day}';
}

int _now() => DateTime.now().millisecondsSinceEpoch;

class AppState extends ChangeNotifier {
  SharedPreferences? _p;
  final List<Task> tasks = [];
  int stardust = 10, xp = 0, pomosToday = 0, cycle = 0;
  double _fullness = 0.7;
  int _fedAt = _now();
  String day = _today();
  String? activeId;
  String petName = 'Luna';

  Phase phase = Phase.focus;
  bool running = false;
  int _endAt = 0;
  int remaining = AppState.dur(Phase.focus);
  Timer? _t;
  int _lastLeft = -1;
  String? event; // one-shot toast message

  static int dur(Phase p) =>
      (p == Phase.focus ? 25 : (p == Phase.short ? 5 : 15)) * 60;

  int get left =>
      running ? math.max(0, ((_endAt - _now()) / 1000).ceil()) : remaining;
  double get progress => 1 - left / dur(phase);
  int get level => xp ~/ 50 + 1;
  double get levelProgress => (xp % 50) / 50;
  double get fullness =>
      (_fullness - (_now() - _fedAt) / 3600000 * 0.05).clamp(0.0, 1.0);

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
    if (running && phase == Phase.focus) return "Shh… we're focusing ✨";
    if (running) return 'Ahh, cozy break~ 💤';
    if (fullness < 0.25) return 'Tummy rumbly… star candy? 🍬';
    if (phase != Phase.focus) return 'Break time! Press play to rest.';
    return "Ready when you are! 🌙";
  }

  // ── persistence
  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    final raw = _p!.getString('s');
    if (raw != null) {
      try {
        final m = jsonDecode(raw) as Map<String, dynamic>;
        tasks
          ..clear()
          ..addAll((m['tasks'] as List? ?? [])
              .map((e) => Task.fromJson(Map<String, dynamic>.from(e as Map))));
        stardust = m['stardust'] as int? ?? stardust;
        xp = m['xp'] as int? ?? 0;
        pomosToday = m['pomosToday'] as int? ?? 0;
        cycle = m['cycle'] as int? ?? 0;
        _fullness = (m['fullness'] as num? ?? 0.7).toDouble();
        _fedAt = m['fedAt'] as int? ?? _now();
        day = m['day'] as String? ?? _today();
        activeId = m['activeId'] as String?;
        petName = m['petName'] as String? ?? 'Luna';
      } catch (_) {}
    }
    if (day != _today()) {
      day = _today();
      pomosToday = 0;
    }
  }

  void _save() {
    _p?.setString(
        's',
        jsonEncode({
          'tasks': tasks.map((t) => t.toJson()).toList(),
          'stardust': stardust,
          'xp': xp,
          'pomosToday': pomosToday,
          'cycle': cycle,
          'fullness': _fullness,
          'fedAt': _fedAt,
          'day': day,
          'activeId': activeId,
          'petName': petName,
        }));
  }

  // ── timer
  void setPhase(Phase p) {
    if (running) return;
    phase = p;
    remaining = dur(p);
    notifyListeners();
  }

  void toggle() {
    HapticFeedback.mediumImpact();
    if (running) {
      remaining = left;
      running = false;
      _t?.cancel();
    } else {
      running = true;
      _endAt = _now() + remaining * 1000;
      _lastLeft = -1;
      _t = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    }
    notifyListeners();
  }

  void reset() {
    _t?.cancel();
    running = false;
    remaining = dur(phase);
    notifyListeners();
  }

  void skip() {
    _t?.cancel();
    running = false;
    _advance();
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

  void _finish() {
    _t?.cancel();
    running = false;
    HapticFeedback.heavyImpact();
    if (phase == Phase.focus) {
      _snapFullness();
      final before = level;
      xp += 10;
      stardust += 5;
      if (day != _today()) {
        day = _today();
        pomosToday = 0;
      }
      pomosToday++;
      activeTask?.pomos++;
      event = level > before
          ? '🌙 Level up! $petName is now Lv $level'
          : '+10 xp  +5 ✨  — nice focus! Break time.';
    } else {
      event = 'Break over — ready to focus?';
    }
    _advance();
    _save();
    notifyListeners();
  }

  void _advance() {
    if (phase == Phase.focus) {
      cycle++;
      phase = cycle % 4 == 0 ? Phase.long : Phase.short;
    } else {
      phase = Phase.focus;
    }
    remaining = dur(phase);
  }

  // ── pet
  void _snapFullness() {
    _fullness = fullness;
    _fedAt = _now();
  }

  bool feed(int cost, double amount) {
    if (stardust < cost) return false;
    _snapFullness();
    _fullness = math.min(1.0, _fullness + amount);
    stardust -= cost;
    xp += 2;
    HapticFeedback.lightImpact();
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

  // ── tasks
  void addTask(String title) {
    if (title.trim().isEmpty) return;
    final t = Task(DateTime.now().microsecondsSinceEpoch.toString(), title.trim());
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

  @override
  void dispose() {
    _t?.cancel();
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

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    widget.s.addListener(_onState);
  }

  @override
  void dispose() {
    widget.s.removeListener(_onState);
    super.dispose();
  }

  void _onState() {
    final e = widget.s.event;
    if (e == null) return;
    widget.s.event = null;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(e, style: const TextStyle(fontWeight: FontWeight.w600)),
        behavior: SnackBarBehavior.floating,
        backgroundColor: const Color(0xFF2B2670),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ));
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
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(children: [
            Row(children: [
              Pill('🌙', 'Lv ${s.level}'),
              const SizedBox(width: 8),
              Pill('✨', '${s.stardust}'),
              const Spacer(),
              Pill('🍅', '${s.pomosToday} today'),
            ]),
            const SizedBox(height: 18),
            _PhaseSelector(s),
            const SizedBox(height: 10),
            SizedBox(
              width: 300,
              height: 320,
              child: Stack(alignment: Alignment.center, children: [
                Positioned.fill(
                    child: CustomPaint(
                        painter: RingPainter(s.progress, brk))),
                Align(
                  alignment: const Alignment(0, -0.22),
                  child: MoonPet(mood: s.mood, level: s.level, size: 210),
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
                  style: const TextStyle(fontSize: 15, color: Colors.white70)),
            ),
            const SizedBox(height: 14),
            GestureDetector(
              onTap: onPlan,
              child: Pill(
                  '🎯',
                  s.activeTask == null
                      ? 'Pick a task in Plan'
                      : s.activeTask!.title),
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
                          color: kPink.withAlpha(90),
                          blurRadius: 24,
                          spreadRadius: 1)
                    ],
                  ),
                  child: Icon(
                      s.running
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
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
    const labels = {
      Phase.focus: 'Focus',
      Phase.short: 'Short',
      Phase.long: 'Long'
    };
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

// ───────────────────────── plan tab ─────────────────────────
class PlanTab extends StatefulWidget {
  const PlanTab(this.s, {super.key});
  final AppState s;
  @override
  State<PlanTab> createState() => _PlanTabState();
}

class _PlanTabState extends State<PlanTab> {
  final _c = TextEditingController();

  void _add() {
    widget.s.addTask(_c.text);
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
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("Tonight's plan",
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            const Text('Tap 🎯 to feed a task to your pomodoros. Swipe to delete.',
                style: TextStyle(color: Colors.white54)),
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
                        hintText: 'Add a wish for tonight…',
                        border: InputBorder.none),
                  ),
                ),
                IconButton.filled(
                  style: IconButton.styleFrom(
                      backgroundColor: kLilac, foregroundColor: kInk),
                  onPressed: _add,
                  icon: const Icon(Icons.add_rounded),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: s.tasks.isEmpty
                  ? const Center(
                      child: Text('Nothing planned yet ✨\nAdd your first task above.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.white38, height: 1.5)))
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 16),
                      itemCount: s.tasks.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => _taskTile(s, s.tasks[i]),
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
            color: Colors.redAccent.withAlpha(70),
            borderRadius: BorderRadius.circular(22)),
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
              child: t.done
                  ? const Icon(Icons.check_rounded, size: 18, color: kInk)
                  : null,
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
          if (t.pomos > 0) Text('🍅×${t.pomos}  ', style: const TextStyle(fontSize: 13)),
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
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF241F5E),
        title: const Text('Name your moon'),
        content: TextField(controller: c, autofocus: true, maxLength: 14),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, c.text), child: const Text('Save')),
        ],
      ),
    );
    c.dispose();
    if (n != null) s.rename(n);
  }

  void _feed(BuildContext context, int cost, double amt) {
    if (!s.feed(cost, amt)) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: const Text('Not enough stardust — go focus to earn some ✨'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF2B2670),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          child: Column(children: [
            Align(alignment: Alignment.centerRight, child: Pill('✨', '${s.stardust}')),
            MoonPet(
                mood: s.mood == Mood.focus || s.mood == Mood.sleepy ? s.mood : (s.fullness < 0.25 ? Mood.sad : Mood.happy),
                level: s.level,
                size: 260),
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
            const SizedBox(height: 14),
            Row(children: [
              Expanded(child: _Feed('🍬', 'Star candy', 5, () => _feed(context, 5, 0.25))),
              const SizedBox(width: 12),
              Expanded(child: _Feed('☁️', 'Cloud milk', 10, () => _feed(context, 10, 0.55))),
            ]),
            const SizedBox(height: 14),
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
        border: Border.all(color: border ?? Colors.white.withAlpha(30), width: border != null ? 1.5 : 1),
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
    canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * rad, 7,
        Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(RingPainter o) => o.progress != progress || o.brk != brk;
}

// ───────────────────────── the moon pet ─────────────────────────
class MoonPet extends StatefulWidget {
  const MoonPet({super.key, required this.mood, required this.level, required this.size});
  final Mood mood;
  final int level;
  final double size;
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
                      level: widget.level),
                ),
              ),
              if (love)
                for (int i = 0; i < 3; i++)
                  Positioned(
                    left: size * (0.28 + 0.2 * i),
                    top: size * 0.22 - p * size * (0.22 + 0.06 * i),
                    child: Opacity(
                      opacity: (1 - p).clamp(0.0, 1.0),
                      child: Text('💗', style: TextStyle(fontSize: 16.0 + i * 5)),
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
  MoonPainter({required this.mood, required this.blink, required this.v, required this.level});
  final Mood mood;
  final bool blink;
  final double v; // 0..1 over 12s
  final int level;

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

  @override
  void paint(Canvas canvas, Size s) {
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
        ..shader = const RadialGradient(
                colors: [Color(0x55FFE9A8), Color(0x00FFE9A8)])
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
        ..shader = const RadialGradient(
          center: Alignment(-0.4, -0.5),
          radius: 1.1,
          colors: [Color(0xFFFFF8DC), Color(0xFFFFE08A), Color(0xFFF5C25B)],
          stops: [0.0, 0.55, 1.0],
        ).createShader(body),
    );

    // craters
    final cr = Paint()..color = const Color(0x22B8860B);
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
        canvas.drawArc(Rect.fromCenter(center: e + Offset(0, r * 0.03), width: r * 0.2, height: r * 0.14),
            math.pi, math.pi, false, stroke);
      } else if (closedU) {
        canvas.drawArc(Rect.fromCenter(center: e - Offset(0, r * 0.03), width: r * 0.2, height: r * 0.14),
            0, math.pi, false, stroke);
      } else {
        canvas.drawOval(Rect.fromCenter(center: e, width: r * 0.17, height: r * 0.25), ink);
        canvas.drawCircle(e + Offset(-r * 0.03, -r * 0.06), r * 0.035, Paint()..color = Colors.white);
      }
      // brows
      if (!closedU && !closedHat && (mood == Mood.focus || mood == Mood.sad)) {
        final inner = mood == Mood.focus ? 0.13 : 0.2; // inner end height
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
          Rect.fromCenter(center: Offset(c.dx + sx * r * 0.63, ey + r * 0.2), width: r * 0.22, height: r * 0.13),
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
        canvas.drawOval(Rect.fromCenter(center: m + Offset(0, r * 0.03), width: r * 0.09, height: r * 0.11),
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
