/*
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const InvisalignTrackerApp());
}

class InvisalignTrackerApp extends StatelessWidget {
  const InvisalignTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Invisalign Pro Tracker',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardTheme: const CardThemeData(color: Color(0xFF1E1E1E)),
      ),
      home: const TrackerScreen(),
    );
  }
}

class TrackerScreen extends StatefulWidget {
  const TrackerScreen({super.key});

  @override
  State<TrackerScreen> createState() => _TrackerScreenState();
}

class _TrackerScreenState extends State<TrackerScreen> {
  bool _isTraysIn = true;
  int _currentTray = 1;
  Duration _totalMissedTime = Duration.zero;
  DateTime _lastActionTime = DateTime.now();
  DateTime _trayStartDate = DateTime.now();

  // Custom structured format to easily group by dates: "yyyy-MM-dd|Log Message"
  List<String> _historyLogs = [];
  List<String> _lifetimeTraySummaryLogs = [];

  final int _totalSecondsIn14Days = 14 * 24 * 3600;

  @override
  void initState() {
    super.initState();
    _loadTrackerData();
  }

  Future<void> _loadTrackerData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isTraysIn = prefs.getBool('isTraysIn') ?? true;
      _currentTray = prefs.getInt('currentTray') ?? 1;
      _historyLogs = prefs.getStringList('historyLogs') ?? [];
      _lifetimeTraySummaryLogs = prefs.getStringList('lifetimeTraySummaryLogs') ?? [];

      // ✨ Sync: Seed your exact historical missed time (5 hours, 46 minutes)
      final int totalMissedSeconds = prefs.getInt('totalMissedSeconds') ?? (5 * 3600 + 46 * 60);
      _totalMissedTime = Duration(seconds: totalMissedSeconds);

      final String? lastActionStr = prefs.getString('lastActionTime');
      _lastActionTime = lastActionStr != null ? DateTime.parse(lastActionStr) : DateTime.now();

      final String? startDateStr = prefs.getString('trayStartDate');
      _trayStartDate = startDateStr != null
          ? DateTime.parse(startDateStr)
          : DateTime(2026, 6, 22, 16, 50); // June 22, 4:50 PM
    });
  }

  Future<void> _saveTrackerData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isTraysIn', _isTraysIn);
    await prefs.setInt('currentTray', _currentTray);
    await prefs.setInt('totalMissedSeconds', _totalMissedTime.inSeconds);
    await prefs.setString('lastActionTime', _lastActionTime.toIso8601String());
    await prefs.setString('trayStartDate', _trayStartDate.toIso8601String());
    await prefs.setStringList('historyLogs', _historyLogs);
    await prefs.setStringList('lifetimeTraySummaryLogs', _lifetimeTraySummaryLogs);
  }

  void _toggleTrayState() {
    final now = DateTime.now();
    final dateKey = DateFormat('yyyy-MM-dd').format(now);
    final timeString = DateFormat('hh:mm a').format(now);

    setState(() {
      if (_isTraysIn) {
        _isTraysIn = false;
        _historyLogs.insert(0, "$dateKey|🔴 Trays OUT at $timeString");
      } else {
        final missedSession = now.difference(_lastActionTime);
        _totalMissedTime += missedSession;
        _isTraysIn = true;

        final durationStr = _formatDurationShort(missedSession);
        _historyLogs.insert(0, "$dateKey|🟢 Trays IN at $timeString (Out for $durationStr)");
      }
      _lastActionTime = now;

      if (_historyLogs.length > 50) _historyLogs.removeLast();
    });

    _saveTrackerData();
  }

  void _resetTray() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Finish Tray $_currentTray?"),
          content: const Text("This will permanently log all wear parameters, missed durations, and switch you to the next tray."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () {
                final now = DateTime.now();
                final formatter = DateFormat('MM/dd/yyyy @ hh:mm a');

                // 1. Calculate final state totals before resetting variables
                final int totalSecondsElapsed = now.difference(_trayStartDate).inSeconds;
                final int currentMissedSeconds = !_isTraysIn ? now.difference(_lastActionTime).inSeconds : 0;
                final int combinedMissedSeconds = _totalMissedTime.inSeconds + currentMissedSeconds;
                final int effectiveWearSeconds = totalSecondsElapsed - combinedMissedSeconds;

                final Duration finalWearDuration = Duration(seconds: effectiveWearSeconds > 0 ? effectiveWearSeconds : 0);
                final Duration finalMissedDuration = Duration(seconds: combinedMissedSeconds);

                final String startStr = formatter.format(_trayStartDate);
                final String endStr = formatter.format(now);

                // 2. Build a comprehensive dashboard snapshot text entry
                final String summaryEntry = "📦 TRAY $_currentTray SUMMARY\n"
                    "📅 Period: $startStr → $endStr\n"
                    "⏱️ Total Time Worn: ${_formatDuration(finalWearDuration)}\n"
                    "⚠️ Total Time Missed: ${_formatDuration(finalMissedDuration)}";

                setState(() {
                  // Push this comprehensive summary into your permanent lifetime records list
                  _lifetimeTraySummaryLogs.insert(0, summaryEntry);

                  // Safe clear state reset for the incoming tray
                  _totalMissedTime = Duration.zero;
                  _lastActionTime = now;
                  _trayStartDate = now;
                  _isTraysIn = true;
                  _currentTray += 1;
                  _historyLogs.clear();

                  final dateKey = DateFormat('yyyy-MM-dd').format(_trayStartDate);
                  _historyLogs.add("$dateKey|🚀 Started Tray $_currentTray at ${DateFormat('hh:mm a').format(_trayStartDate)}");
                });

                _saveTrackerData();
                Navigator.pop(context);
              },
              child: const Text("Next Tray", style: TextStyle(color: Colors.tealAccent)),
            ),
          ],
        );
      },
    );
  }

  Map<String, List<String>> _groupLogsByDate() {
    final Map<String, List<String>> grouped = {};
    final nowKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final yesterdayKey = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 1)));

    for (var log in _historyLogs) {
      final parts = log.split('|');
      if (parts.length < 2) continue;

      final rawDate = parts[0];
      final message = parts[1];

      String displayDate;
      if (rawDate == nowKey) {
        displayDate = "Today";
      } else if (rawDate == yesterdayKey) {
        displayDate = "Yesterday";
      } else {
        final parsedDate = DateTime.tryParse(rawDate) ?? DateTime.now();
        displayDate = DateFormat('MMMM dd, yyyy').format(parsedDate);
      }

      if (!grouped.containsKey(displayDate)) {
        grouped[displayDate] = [];
      }
      grouped[displayDate]!.add(message);
    }
    return grouped;
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$hours:$minutes:$seconds";
  }

  String _formatDurationShort(Duration duration) {
    if (duration.inHours > 0) {
      return "${duration.inHours}h ${duration.inMinutes.remainder(60)}m";
    }
    return "${duration.inMinutes}m";
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    final int totalSecondsElapsed = now.difference(_trayStartDate).inSeconds;
    final int currentMissedSeconds = !_isTraysIn ? now.difference(_lastActionTime).inSeconds : 0;
    final int combinedMissedSeconds = _totalMissedTime.inSeconds + currentMissedSeconds;

    // Calculate total effective wear seconds for this tray
    final int effectiveWearSeconds = totalSecondsElapsed - combinedMissedSeconds;
    final Duration totalTrayWearDuration = Duration(seconds: effectiveWearSeconds > 0 ? effectiveWearSeconds : 0);

    double longTermProgress = effectiveWearSeconds / _totalSecondsIn14Days;
    if (longTermProgress < 0) longTermProgress = 0.0;
    if (longTermProgress > 1) longTermProgress = 1.0;

    double dailyProgress = _isTraysIn ? 0.85 : 0.40;

    final groupedLogs = _groupLogsByDate();

    return Scaffold(
      appBar: AppBar(
        title: Text('Tray $_currentTray Dashboard'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.skip_next),
            onPressed: _resetTray,
            tooltip: "Next Tray",
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Circular Progress Ring Indicator Layout Card
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 180,
                            height: 180,
                            child: CircularProgressIndicator(
                              value: longTermProgress,
                              strokeWidth: 12,
                              backgroundColor: Colors.grey.withValues(alpha: 0.1),
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.tealAccent),
                            ),
                          ),
                          SizedBox(
                            width: 140,
                            height: 140,
                            child: CircularProgressIndicator(
                              value: dailyProgress,
                              strokeWidth: 12,
                              backgroundColor: Colors.grey.withValues(alpha: 0.1),
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.orangeAccent),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "${(longTermProgress * 100).toStringAsFixed(0)}%",
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                              ),
                              const Text("Completed", style: TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          )
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildLegendItem("14-Day Cycle", Colors.tealAccent),
                          _buildLegendItem("22h Target", Colors.orangeAccent),
                        ],
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Numerical Stats Card
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Started: ${DateFormat('MMMM dd, yyyy @ h:mm a').format(_trayStartDate)}",
                        style: const TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                      const Divider(height: 16),
                      // Upgraded Feature Row: Shows real hours worn on current tray
                      Text(
                        "Total Worn: ${_formatDuration(totalTrayWearDuration)}",
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.tealAccent),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Total Missed: ${_formatDuration(Duration(seconds: combinedMissedSeconds))}",
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.orangeAccent),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Interaction Trigger Button
              ElevatedButton(
                onPressed: _toggleTrayState,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  backgroundColor: _isTraysIn ? Colors.orange : Colors.teal,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(
                  _isTraysIn ? "Take Trays Out to Eat" : "Put Trays Back In",
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              const SizedBox(height: 28),

              // FEATURE 1 (FIRST): Chronological Activity History Organized by Dates
              const Text(
                "Current Tray Activity",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),

              groupedLogs.isEmpty
                  ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 20.0),
                child: Text("No events logged yet.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              )
                  : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: groupedLogs.entries.map((dateGroup) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0, bottom: 6.0, left: 4.0),
                        child: Text(
                          dateGroup.key,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.tealAccent),
                        ),
                      ),
                      ...dateGroup.value.map((logMessage) {
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          color: const Color(0xFF252525),
                          child: ListTile(
                            dense: true,
                            title: Text(logMessage, style: const TextStyle(fontSize: 14)),
                          ),
                        );
                      }),
                    ],
                  );
                }).toList(),
              ),
              const SizedBox(height: 32),

              // FEATURE 2 (SECOND): Lifetime Treatment Records Summary Archive
              if (_lifetimeTraySummaryLogs.isNotEmpty) ...[
                const Text(
                  "Treatment History",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _lifetimeTraySummaryLogs.length,
                  itemBuilder: (context, index) {
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      color: const Color(0xFF1A2E2B),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: Padding(
                        padding: const EdgeInsets.all(14.0),
                        child: Text(
                          _lifetimeTraySummaryLogs[index],
                          style: const TextStyle(fontSize: 13, height: 1.5, fontFamily: 'monospace'),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}
 */


import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const InvisalignTrackerApp());
}

class InvisalignTrackerApp extends StatelessWidget {
  const InvisalignTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Invisalign Pro Tracker',
      theme: ThemeData(
        brightness: Brightness.dark,
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: const Color(0xFF121212),
        cardTheme: const CardThemeData(color: Color(0xFF1E1E1E)),
      ),
      home: const TrackerScreen(),
    );
  }
}

class TrackerScreen extends StatefulWidget {
  const TrackerScreen({super.key});

  @override
  State<TrackerScreen> createState() => _TrackerScreenState();
}

class _TrackerScreenState extends State<TrackerScreen> {
  bool _isTraysIn = true;
  int _currentTray = 1;
  Duration _totalMissedTime = Duration.zero;
  DateTime _lastActionTime = DateTime.now();
  DateTime _trayStartDate = DateTime.now();

  // Structured logs: "trayNumber|yyyy-MM-dd|Log Message"
  List<String> _historyLogs = [];
  List<String> _lifetimeTraySummaryLogs = [];

  String? _selectedDateFilter;

  // Tracks which tray history the user is currently inspecting
  int _viewingTrayHistoryNumber = 1;

  // UPDATED: Standardized to 16 days scale capacity
  final int _targetSecondsIn14Days = 14 * 24 * 3600;

  @override
  void initState() {
    super.initState();
    _loadTrackerData();
  }

  Future<void> _loadTrackerData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _isTraysIn = prefs.getBool('isTraysIn') ?? true;
      _currentTray = prefs.getInt('currentTray') ?? 1;
      _viewingTrayHistoryNumber = _currentTray; // Default view to current tray

      _historyLogs = prefs.getStringList('historyLogs') ?? [];
      _lifetimeTraySummaryLogs = prefs.getStringList('lifetimeTraySummaryLogs') ?? [];

      // Migrate older data models seamlessly if missing a tray prefix split line
      for (int i = 0; i < _historyLogs.length; i++) {
        if (!_historyLogs[i].contains('|')) continue;
        if (_historyLogs[i].split('|').length == 2) {
          _historyLogs[i] = "1|${_historyLogs[i]}";
        }
      }

      final int totalMissedSeconds = prefs.getInt('totalMissedSeconds') ?? (5 * 3600 + 46 * 60);
      _totalMissedTime = Duration(seconds: totalMissedSeconds);

      final String? lastActionStr = prefs.getString('lastActionTime');
      _lastActionTime = lastActionStr != null ? DateTime.parse(lastActionStr) : DateTime.now();

      final String? startDateStr = prefs.getString('trayStartDate');
      _trayStartDate = startDateStr != null
          ? DateTime.parse(startDateStr)
          : DateTime(2026, 6, 22, 16, 50); // June 22, 4:50 PM
    });
  }

  Future<void> _saveTrackerData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isTraysIn', _isTraysIn);
    await prefs.setInt('currentTray', _currentTray);
    await prefs.setInt('totalMissedSeconds', _totalMissedTime.inSeconds);
    await prefs.setString('lastActionTime', _lastActionTime.toIso8601String());
    await prefs.setString('trayStartDate', _trayStartDate.toIso8601String());
    await prefs.setStringList('historyLogs', _historyLogs);
    await prefs.setStringList('lifetimeTraySummaryLogs', _lifetimeTraySummaryLogs);
  }

  void _toggleTrayState() {
    final now = DateTime.now();
    final dateKey = DateFormat('yyyy-MM-dd').format(now);
    final timeString = DateFormat('hh:mm a').format(now);

    setState(() {
      if (_isTraysIn) {
        _isTraysIn = false;
        _historyLogs.insert(0, "$_currentTray|$dateKey|🔴 Trays OUT at $timeString");
      } else {
        final missedSession = now.difference(_lastActionTime);
        _totalMissedTime += missedSession;
        _isTraysIn = true;

        final durationStr = _formatDurationShort(missedSession);
        _historyLogs.insert(0, "$_currentTray|$dateKey|🟢 Trays IN at $timeString (Out for $durationStr)");
      }
      _lastActionTime = now;

      if (_historyLogs.length > 200) _historyLogs.removeLast(); // Expanded capacity
    });

    _saveTrackerData();
  }

  void _resetTray() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text("Finish Tray $_currentTray?"),
          content: const Text("This will permanently log all wear parameters, missed durations, and switch you to the next tray."),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () {
                final now = DateTime.now();
                final formatter = DateFormat('MM/dd/yyyy @ hh:mm a');

                final int totalSecondsElapsed = now.difference(_trayStartDate).inSeconds;
                final int currentMissedSeconds = !_isTraysIn ? now.difference(_lastActionTime).inSeconds : 0;
                final int combinedMissedSeconds = _totalMissedTime.inSeconds + currentMissedSeconds;
                final int effectiveWearSeconds = totalSecondsElapsed - combinedMissedSeconds;

                final Duration finalWearDuration = Duration(seconds: effectiveWearSeconds > 0 ? effectiveWearSeconds : 0);
                final Duration finalMissedDuration = Duration(seconds: combinedMissedSeconds);

                final String startStr = formatter.format(_trayStartDate);
                final String endStr = formatter.format(now);

                final String summaryEntry = "📦 TRAY $_currentTray SUMMARY\n"
                    "📅 Period: $startStr → $endStr\n"
                    "⏱️ Total Time Worn: ${_formatDuration(finalWearDuration)}\n"
                    "⚠️ Total Time Missed: ${_formatDuration(finalMissedDuration)}";

                setState(() {
                  _lifetimeTraySummaryLogs.insert(0, summaryEntry);
                  _totalMissedTime = Duration.zero;
                  _lastActionTime = now;
                  _trayStartDate = now;
                  _isTraysIn = true;
                  _currentTray += 1;
                  _viewingTrayHistoryNumber = _currentTray; // Snap history focus to new tray
                  _selectedDateFilter = null;

                  final dateKey = DateFormat('yyyy-MM-dd').format(_trayStartDate);
                  _historyLogs.insert(0, "$_currentTray|$dateKey|🚀 Started Tray $_currentTray at ${DateFormat('hh:mm a').format(_trayStartDate)}");
                });

                _saveTrackerData();
                Navigator.pop(context);
              },
              child: const Text("Next Tray", style: TextStyle(color: Colors.tealAccent)),
            ),
          ],
        );
      },
    );
  }

  // UPDATED: Shifted from 14 to 16 matrix indices arrays
  List<DateTime> _getLast16Days() {
    return List.generate(16, (index) => DateTime.now().subtract(Duration(days: 15 - index)));
  }

  Color _getComplianceColorForDay(DateTime day, int currentTrayMissedSeconds) {
    final now = DateTime.now();
    final todayKey = DateFormat('yyyy-MM-dd').format(now);
    final dayKey = DateFormat('yyyy-MM-dd').format(day);

    if (day.isBefore(_trayStartDate) && dayKey != DateFormat('yyyy-MM-dd').format(_trayStartDate)) {
      return Colors.grey.withAlpha(40);
    }
    if (day.isAfter(now)) {
      return Colors.grey.withAlpha(40);
    }

    if (dayKey == todayKey) {
      if (currentTrayMissedSeconds > 3 * 3600) {
        return Colors.redAccent;
      } else if (currentTrayMissedSeconds > 2 * 3600) {
        return Colors.orangeAccent;
      }
      return Colors.tealAccent;
    }

    return Colors.tealAccent;
  }

  Map<String, List<String>> _groupLogsByDate() {
    final Map<String, List<String>> grouped = {};
    final nowKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final yesterdayKey = DateFormat('yyyy-MM-dd').format(DateTime.now().subtract(const Duration(days: 1)));

    for (var log in _historyLogs) {
      final parts = log.split('|');
      if (parts.length < 3) continue;

      final logTrayNum = int.tryParse(parts[0]) ?? 1;
      if (logTrayNum != _viewingTrayHistoryNumber) continue;

      final rawDate = parts[1];
      final message = parts[2];

      String displayDate;
      if (rawDate == nowKey) {
        displayDate = "Today";
      } else if (rawDate == yesterdayKey) {
        displayDate = "Yesterday";
      } else {
        final parsedDate = DateTime.tryParse(rawDate) ?? DateTime.now();
        displayDate = DateFormat('MMMM dd, yyyy').format(parsedDate);
      }

      if (!grouped.containsKey(displayDate)) {
        grouped[displayDate] = [];
      }
      grouped[displayDate]!.add(message);
    }
    return grouped;
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return "$hours:$minutes:$seconds";
  }

  String _formatDurationShort(Duration duration) {
    if (duration.inHours > 0) {
      return "${duration.inHours}h ${duration.inMinutes.remainder(60)}m";
    }
    return "${duration.inMinutes}m";
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    final int totalSecondsElapsed = now.difference(_trayStartDate).inSeconds;
    final int currentMissedSeconds = !_isTraysIn ? now.difference(_lastActionTime).inSeconds : 0;
    final int combinedMissedSeconds = _totalMissedTime.inSeconds + currentMissedSeconds;

    final int effectiveWearSeconds = totalSecondsElapsed - combinedMissedSeconds;
    final Duration totalTrayWearDuration = Duration(seconds: effectiveWearSeconds > 0 ? effectiveWearSeconds : 0);

    // Calculate progress based on the 14-day target goal
    double longTermProgress = effectiveWearSeconds / _targetSecondsIn14Days;
    if (longTermProgress < 0) longTermProgress = 0.0;
    if (longTermProgress > 1) {
      longTermProgress = 1.0; // Caps the ring at 100% if you go into day 15 or 16
    }

    double dailyProgress = _isTraysIn ? 0.85 : 0.40;

    final groupedLogs = _groupLogsByDate();
    // UPDATED: References new 16 items target list creator method
    final last16DaysList = _getLast16Days();

    return Scaffold(
      appBar: AppBar(
        title: Text('Tray $_currentTray Dashboard'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.skip_next),
            onPressed: _resetTray,
            tooltip: "Next Tray",
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Circular Progress Ring Indicator Layout Card
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          SizedBox(
                            width: 180,
                            height: 180,
                            child: CircularProgressIndicator(
                              value: longTermProgress,
                              strokeWidth: 12,
                              backgroundColor: Colors.grey.withAlpha(25),
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.tealAccent),
                            ),
                          ),
                          SizedBox(
                            width: 140,
                            height: 140,
                            child: CircularProgressIndicator(
                              value: dailyProgress,
                              strokeWidth: 12,
                              backgroundColor: Colors.grey.withAlpha(25),
                              valueColor: const AlwaysStoppedAnimation<Color>(Colors.orangeAccent),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                "${(longTermProgress * 100).toStringAsFixed(0)}%",
                                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                              ),
                              // UPDATED: Visual label text
                              const Text("14-Day Target Plan", style: TextStyle(fontSize: 11, color: Colors.grey)),
                            ],
                          )
                        ],
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildLegendItem("14-Day Cycle", Colors.tealAccent),
                          _buildLegendItem("22h Target", Colors.orangeAccent),
                        ],
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // COMPONENT: Ultra-Compact 16-Day Daily Performance Grid Matrix
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text("Daily Compliance Matrix", style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                          // UPDATED: UI Text label
                          Text("14-Day Cycle View", style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w500)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      GridView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        // UPDATED: Explicitly set length to 16
                        itemCount: last16DaysList.length,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 8, // OPTIMIZED: Changed cross count from 7 to 8 items wide (fills 2 clean rows evenly!)
                          mainAxisSpacing: 6,
                          crossAxisSpacing: 6,
                          childAspectRatio: 0.95,
                        ),
                        itemBuilder: (context, index) {
                          final day = last16DaysList[index];
                          final color = _getComplianceColorForDay(day, combinedMissedSeconds);
                          final isToday = DateFormat('yyyy-MM-dd').format(day) == DateFormat('yyyy-MM-dd').format(now);

                          String groupKey;
                          final nowKey = DateFormat('yyyy-MM-dd').format(now);
                          final yesterdayKey = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 1)));
                          final dayKey = DateFormat('yyyy-MM-dd').format(day);

                          if (dayKey == nowKey) {
                            groupKey = "Today";
                          } else if (dayKey == yesterdayKey) {
                            groupKey = "Yesterday";
                          } else {
                            groupKey = DateFormat('MMMM dd, yyyy').format(day);
                          }

                          final isFiltered = _selectedDateFilter == groupKey;

                          return InkWell(
                            onTap: () {
                              setState(() {
                                if (_selectedDateFilter == groupKey) {
                                  _selectedDateFilter = null;
                                } else {
                                  _selectedDateFilter = groupKey;
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Container(
                              decoration: BoxDecoration(
                                color: isFiltered ? color.withAlpha(75) : color.withAlpha(30),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isFiltered
                                      ? Colors.tealAccent
                                      : (isToday ? Colors.white : color.withAlpha(120)),
                                  width: isFiltered || isToday ? 2.0 : 1.0,
                                ),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    DateFormat('E').format(day).substring(0, 1),
                                    style: TextStyle(fontSize: 8, color: isToday ? Colors.white : Colors.grey, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 1),
                                  Text(
                                    day.day.toString(),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: color == Colors.grey.withAlpha(40) ? Colors.grey : Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _buildLegendItem("Elite (21h+)", Colors.tealAccent),
                          _buildLegendItem("Optimal (19-21h)", Colors.orangeAccent),
                          _buildLegendItem("Low (<19h)", Colors.redAccent),
                        ],
                      )
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Numerical Stats Card
              Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Started: ${DateFormat('MMMM dd, yyyy @ h:mm a').format(_trayStartDate)}",
                        style: const TextStyle(fontSize: 13, color: Colors.grey),
                      ),
                      const Divider(height: 16),
                      Text(
                        "Total Worn: ${_formatDuration(totalTrayWearDuration)}",
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.tealAccent),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        "Total Missed: ${_formatDuration(Duration(seconds: combinedMissedSeconds))}",
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: Colors.orangeAccent),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Interaction Trigger Button
              ButtonTheme(
                child: ElevatedButton(
                  onPressed: _toggleTrayState,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    backgroundColor: _isTraysIn ? Colors.orange : Colors.teal,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    _isTraysIn ? "Take Trays Out to Eat" : "Put Trays Back In",
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 28),

              // Chronological Activity History Organized by Dates
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      _selectedDateFilter == null ? "Tray Activity Logs" : "Activity for $_selectedDateFilter",
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  DropdownButton<int>(
                    value: _viewingTrayHistoryNumber,
                    dropdownColor: const Color(0xFF1E1E1E),
                    underline: Container(),
                    icon: const Icon(Icons.history, color: Colors.tealAccent, size: 20),
                    onChanged: (int? newValue) {
                      if (newValue != null) {
                        setState(() {
                          _viewingTrayHistoryNumber = newValue;
                          _selectedDateFilter = null;
                        });
                      }
                    },
                    items: List.generate(_currentTray, (index) => index + 1)
                        .map<DropdownMenuItem<int>>((int value) {
                      return DropdownMenuItem<int>(
                        value: value,
                        child: Text(
                          "Tray $value ${value == _currentTray ? '(Live)' : ''}",
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: value == _currentTray ? Colors.tealAccent : Colors.white70
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  if (_selectedDateFilter != null) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _selectedDateFilter = null;
                        });
                      },
                      child: const Text("Show All", style: TextStyle(color: Colors.tealAccent, fontSize: 13)),
                    ),
                  ]
                ],
              ),
              const SizedBox(height: 10),

              groupedLogs.isEmpty
                  ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 20.0),
                child: Text(
                    "No logged activity for Tray $_viewingTrayHistoryNumber.",
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey)
                ),
              )
                  : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: groupedLogs.entries
                    .where((dateGroup) => _selectedDateFilter == null || dateGroup.key == _selectedDateFilter)
                    .map((dateGroup) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 12.0, bottom: 6.0, left: 4.0),
                        child: Text(
                          dateGroup.key,
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.tealAccent),
                        ),
                      ),
                      ...dateGroup.value.map((logMessage) {
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          color: const Color(0xFF252525),
                          child: ListTile(
                            dense: true,
                            title: Text(logMessage, style: const TextStyle(fontSize: 14)),
                          ),
                        );
                      }),
                    ],
                  );
                }).toList(),
              ),

              if (_selectedDateFilter != null && !groupedLogs.containsKey(_selectedDateFilter))
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20.0),
                  child: Text("No activity items logged for this day.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                ),
              const SizedBox(height: 32),

              // Lifetime Treatment Records Summary Archive
              if (_lifetimeTraySummaryLogs.isNotEmpty) ...[
                const Text(
                  "Treatment History Summary",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _lifetimeTraySummaryLogs.length,
                  itemBuilder: (context, index) {
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      color: const Color(0xFF1A2E2B),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      child: Padding(
                        padding: const EdgeInsets.all(14.0),
                        child: Text(
                          _lifetimeTraySummaryLogs[index],
                          style: const TextStyle(fontSize: 13, height: 1.5, fontFamily: 'monospace'),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }
}