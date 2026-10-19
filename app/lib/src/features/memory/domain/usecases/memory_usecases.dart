import 'package:injectable/injectable.dart';

import '../entities/memory.dart';
import '../entities/memory_enums.dart';
import '../repositories/memory_repository.dart';

/// Parameters for a library page request.
typedef FetchMemoriesParams = ({
  int limit,
  int offset,
  Set<MemoryType> types,
  ProcessingStatus? status,
});

@injectable
class FetchMemories {
  const FetchMemories(this._repository);

  final MemoryRepository _repository;

  Future<MemoryPage> call(FetchMemoriesParams params) =>
      _repository.fetchMemories(
        limit: params.limit,
        offset: params.offset,
        types: params.types,
        status: params.status,
      );

  /// The first page from this device's copy, for drawing before [call]
  /// returns. Null when there is nothing cached.
  Future<MemoryPage?> cached(FetchMemoriesParams params) =>
      _repository.cachedMemories(
        limit: params.limit,
        types: params.types,
        status: params.status,
      );
}

@injectable
class GetMemory {
  const GetMemory(this._repository);

  final MemoryRepository _repository;

  Future<Memory> call(String id) => _repository.fetchMemory(id);
}

/// Capture a thought, a block of text, or a link.
typedef CaptureParams = ({
  MemoryType type,
  String? title,
  String? text,
  String? url,
});

@injectable
class CaptureMemory {
  const CaptureMemory(this._repository);

  final MemoryRepository _repository;

  Future<Memory> call(CaptureParams params) => _repository.capture(
    type: params.type,
    title: params.title,
    text: params.text,
    url: params.url,
  );
}

/// Deletes the memory only — never the original file. Removing a file from the
/// user's own storage is a separate, explicitly confirmed action (§36).
@injectable
class DeleteMemory {
  const DeleteMemory(this._repository);

  final MemoryRepository _repository;

  Future<void> call(String id) => _repository.deleteMemory(id);
}
