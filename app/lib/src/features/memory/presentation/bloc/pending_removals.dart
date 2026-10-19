import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/error/error_mapper.dart';
import '../../../../core/feedback/snack.dart';
import '../../../../core/feedback/snack_controller.dart';
import '../../domain/repositories/memory_repository.dart';

/// Removing a memory, with the design's five seconds to take it back (2E).
///
/// **Nothing is deleted until the window closes.** The undo snack is the
/// one destructive path in the system, and its ring draining is the promise
/// "nothing goes without your confirmation" made visible. So the delete is
/// *scheduled*, not performed: Undo cancels a timer, and nothing has to be
/// restored — which matters, because a deleted memory takes its chunks with
/// it and could only come back by indexing the file again.
///
/// While a removal is pending the memory is hidden, not gone: the Library
/// leaves it out of the list ([hidden]) so the removal looks immediate, and
/// puts it back if the user changes their mind.
///
/// App-wide, because the screen that asked — the file viewer — closes the
/// moment Remove is tapped, and the window has to outlive it.
@lazySingleton
class PendingRemovals extends ChangeNotifier {
  PendingRemovals(this._memories, this._snacks);

  final MemoryRepository _memories;
  final SnackController _snacks;

  final _timers = <String, Timer>{};

  /// Deleted for good. Still hidden: the Library's list is a fetched page,
  /// and until it next reloads it would otherwise show the row again.
  final _gone = <String>{};

  /// The window — the undo snack's own hold, so the ring and the delete end
  /// together.
  static const window = Duration(seconds: 5);

  /// Memories on their way out, or already gone. The Library hides these.
  Set<String> get hidden => {..._timers.keys, ..._gone};

  /// Hide [memoryId] now, and delete it when the window closes.
  void remove(String memoryId) {
    if (_timers.containsKey(memoryId)) return;
    _timers[memoryId] = Timer(window, () => unawaited(_commit(memoryId)));
    notifyListeners();
    _snacks.show(
      Snack.undo(message: 'Memory removed', onUndo: () => undo(memoryId)),
    );
  }

  /// Take it back: the timer goes, and so does the hiding.
  void undo(String memoryId) {
    _timers.remove(memoryId)?.cancel();
    notifyListeners();
  }

  Future<void> _commit(String memoryId) async {
    try {
      await _memories.deleteMemory(memoryId);
      _gone.add(memoryId);
    } catch (error, stackTrace) {
      // Back in the list, because it is still in the index — and the
      // design's own words for why.
      _snacks.show(
        Snack.detail(
          title: 'Could not remove it',
          subtitle: ErrorMapper.map(error, stackTrace).displayMessage,
          mark: SnackMark.failure,
        ),
      );
    } finally {
      _timers.remove(memoryId);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    super.dispose();
  }
}
