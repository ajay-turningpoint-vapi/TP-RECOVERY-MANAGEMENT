import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:salesman_mobile/services/api_client.dart';

/// One decoded Server-Sent Event from `GET /api/events`.
class RealtimeEvent {
  final String type; // 'invalidate' | 'sync' | 'notification' | ...
  final Map<String, dynamic> data;
  const RealtimeEvent(this.type, this.data);
}

/// Holds a single long-lived SSE connection to the server and turns the
/// pushed events into a [Stream]. Replaces all of AppStore's polling
/// timers. Reconnects on its own with exponential backoff; a 60s "no bytes
/// received" watchdog forces a reconnect if the stream silently dies
/// (the server heartbeats every 20s, so a healthy stream never trips it).
class RealtimeClient {
  RealtimeClient(this._api);

  final ApiClient _api;

  final _events = StreamController<RealtimeEvent>.broadcast();
  final _connState = StreamController<bool>.broadcast();

  /// Server events (invalidate / sync / notification).
  Stream<RealtimeEvent> get events => _events.stream;

  /// `true` on each successful (re)connect, `false` when the stream drops.
  Stream<bool> get connectionState => _connState.stream;

  http.Client _http = http.Client();
  StreamSubscription<String>? _sub;
  Timer? _reconnectTimer;
  Timer? _deadTimer;
  int _backoffMs = 1000;
  bool _running = false;
  bool _connected = false;

  // SSE frame accumulators.
  String? _evtType;
  final StringBuffer _dataBuf = StringBuffer();

  void start() {
    if (_running) return;
    _running = true;
    _backoffMs = 1000;
    _connect();
  }

  void stop() {
    _running = false;
    _reconnectTimer?.cancel();
    _deadTimer?.cancel();
    _sub?.cancel();
    _sub = null;
    _setConnected(false);
    try {
      _http.close();
    } catch (_) {}
    _http = http.Client(); // fresh client for a later start()
  }

  void dispose() {
    stop();
    _events.close();
    _connState.close();
  }

  // ------------------------------------------------------------------

  Future<void> _connect() async {
    if (!_running) return;
    _reconnectTimer?.cancel();
    _sub?.cancel();
    _sub = null;
    _evtType = null;
    _dataBuf.clear();

    try {
      final req = http.Request('GET', Uri.parse('${_api.baseUrl}/api/events'))
        ..headers.addAll(_api.eventStreamHeaders)
        ..persistentConnection = true;
      final resp = await _http.send(req).timeout(const Duration(seconds: 20));

      if (resp.statusCode == 401) {
        // The 1h access token expired under the long-lived stream. Refresh
        // once (shared single-flight) and retry soon; if refresh fails,
        // ApiClient.onSessionExpired has already fired.
        final ok = await _api.ensureFreshToken();
        _scheduleReconnect(delayMs: ok ? 500 : null);
        return;
      }
      if (resp.statusCode != 200) {
        _scheduleReconnect();
        return;
      }

      _backoffMs = 1000; // clean connect resets backoff
      _setConnected(true);
      _armDeadTimer();

      _sub = resp.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            _onLine,
            onError: (_) => _onDrop(),
            onDone: _onDrop,
            cancelOnError: true,
          );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onLine(String line) {
    _armDeadTimer(); // any byte (data OR ':' heartbeat) means the pipe is alive

    if (line.isEmpty) {
      // Blank line terminates one event.
      final raw = _dataBuf.toString();
      final type = _evtType;
      _evtType = null;
      _dataBuf.clear();
      if (type == null || raw.isEmpty) return;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) _events.add(RealtimeEvent(type, decoded));
      } catch (_) {/* ignore a malformed frame */}
      return;
    }
    if (line.startsWith(':')) return; // comment / heartbeat
    final idx = line.indexOf(':');
    final field = idx == -1 ? line : line.substring(0, idx);
    var value = idx == -1 ? '' : line.substring(idx + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    if (field == 'event') {
      _evtType = value;
    } else if (field == 'data') {
      if (_dataBuf.isNotEmpty) _dataBuf.write('\n');
      _dataBuf.write(value);
    }
    // 'id' / 'retry' fields ignored.
  }

  void _onDrop() {
    _sub?.cancel();
    _sub = null;
    _setConnected(false);
    _scheduleReconnect();
  }

  void _armDeadTimer() {
    _deadTimer?.cancel();
    _deadTimer = Timer(const Duration(seconds: 60), () {
      // No bytes for 60s despite a 20s server heartbeat — treat as dead.
      _onDrop();
    });
  }

  void _scheduleReconnect({int? delayMs}) {
    if (!_running) return;
    _reconnectTimer?.cancel();
    final wait = delayMs ?? _backoffMs;
    _reconnectTimer = Timer(Duration(milliseconds: wait), _connect);
    if (delayMs == null) {
      _backoffMs = math.min(_backoffMs * 2, 30000);
    }
  }

  void _setConnected(bool value) {
    if (_connected == value) return;
    _connected = value;
    if (!_connState.isClosed) _connState.add(value);
  }
}
