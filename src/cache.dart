import 'dart:async';

class Cache<K, V> {
    static bool enabled = false;

    final Map<K, V> _cache = {};
    final Map<K, DateTime> _expirationTimes = {};
    final Duration expirationDuration;
    Timer? _clearTimer;
    Timer? get clearTimer => _clearTimer;

    Cache({
        this.expirationDuration = const Duration(hours: 4),
        Duration? clearInterval
    }) {
        if (clearInterval != null) {
            setClearTimer(clearInterval);
        }
    }

    Timer setClearTimer(Duration duration) {
        if (_clearTimer != null) {
            _clearTimer!.cancel();
        }
        return _clearTimer = Timer.periodic(duration, (timer) {
            DateTime now = DateTime.now();
            _expirationTimes.removeWhere((key, expiration) => expiration.isBefore(now));
            _cache.removeWhere((key, value) => !_expirationTimes.containsKey(key));
        });
    }

    void set(K key, V value) {
        _cache[key] = value;
        _expirationTimes[key] = DateTime.now().add(expirationDuration);
    }

    V? get(K key) {
        if (!enabled) return null;
        if (_cache.containsKey(key)) {
            if (_expirationTimes[key]!.isAfter(DateTime.now())) {
                return _cache[key];
            } else {
                _cache.remove(key);
                _expirationTimes.remove(key);
            }
        }
        return null;
    }

    void remove(K key) {
        _cache.remove(key);
        _expirationTimes.remove(key);
    }

    void clear() {
        _cache.clear();
        _expirationTimes.clear();
    }
}