import 'dart:collection';

class TransactionQueue {
  static final Queue<Map<String, dynamic>> _queue = Queue();
  static bool _isProcessing = false;

  static Future<void> addToQueue(Future<void> Function() task) async {
    _queue.add({'task': task});
    if (!_isProcessing) {
      await _processQueue();
    }
  }

  static Future<void> _processQueue() async {
    if (_isProcessing) return;
    _isProcessing = true;

    while (_queue.isNotEmpty) {
      final item = _queue.removeFirst();
      print("📋 Traitement en cours... (${_queue.length + 1} restants)");

      try {
        await (item['task'] as Future<void> Function())();
        print("✅ Tâche terminée");
      } catch (e) {
        print("❌ Erreur: $e");
      }

      // Pause facultative entre les traitements
      await Future.delayed(Duration(seconds: 1));
    }

    _isProcessing = false;
    print("🏁 File d'attente terminée");
  }
}