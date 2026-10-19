import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:injectable/injectable.dart';

import '../../../../core/bloc/safe_emit.dart';
import '../../../../core/error/app_exception.dart';
import '../../../../core/error/error_mapper.dart';
import '../../domain/entities/memory.dart';
import '../../domain/usecases/memory_usecases.dart';

part 'file_viewer_cubit.freezed.dart';

@freezed
abstract class FileViewerState with _$FileViewerState {
  const factory FileViewerState({
    Memory? memory,

    /// The extracted text, cut into readable pages. See
    /// [FileViewerCubit.paginate].
    @Default(<String>[]) List<String> pages,
    @Default(0) int page,
    @Default(true) bool isLoading,
    AppException? exception,
  }) = _FileViewerState;

  const FileViewerState._();

  /// Never zero — a document with no extracted text is still one page, and a
  /// header reading "PAGE 1 OF 0" is worse than an empty page.
  int get pageCount => pages.isEmpty ? 1 : pages.length;

  String get pageLabel => 'PAGE ${page + 1} OF $pageCount';

  String get body =>
      pages.isEmpty ? '' : pages[page.clamp(0, pages.length - 1)];
}

/// Screen 1M — FILE VIEWER.
///
/// **It reads the index, not the file.** The obvious implementation of a file
/// viewer fetches the original and renders it, which for a Drive PDF means a
/// download before anything appears — and on a phone that captured nothing,
/// the original may not be reachable at all. What Hawk always has is the text
/// it extracted, which is the thing the answers were built from, so that is
/// what the viewer shows. "Open in app" is there for the genuine article.
///
/// That is also why the header can say "PAGE 2 OF 6" at all: the page count
/// is of the extracted text, not of the source document. The provider's own
/// pagination is not in the index and never was.
@injectable
class FileViewerCubit extends Cubit<FileViewerState>
    with SafeEmit<FileViewerState> {
  FileViewerCubit(this._getMemory, @factoryParam this._memoryId)
    : super(const FileViewerState()) {
    load();
  }

  final GetMemory _getMemory;
  final String _memoryId;

  Future<void> load() async {
    emit(state.copyWith(isLoading: true, exception: null));
    try {
      final memory = await _getMemory(_memoryId);
      emit(
        state.copyWith(
          isLoading: false,
          memory: memory,
          pages: paginate(memory.text),
          page: 0,
        ),
      );
    } catch (error, stackTrace) {
      emit(
        state.copyWith(
          isLoading: false,
          exception: ErrorMapper.map(error, stackTrace),
        ),
      );
    }
  }

  void showPage(int index) {
    if (index < 0 || index >= state.pageCount) return;
    emit(state.copyWith(page: index));
  }

  void dismissError() => emit(state.copyWith(exception: null));

  /// Cuts extracted text into pages at paragraph boundaries.
  ///
  /// Not measured against the viewport, deliberately. A measured pagination
  /// re-flows when the text size changes, which means the page count in the
  /// header changes under somebody who turned on larger type — and the
  /// paragraph a citation pointed at moves. Cutting on a character budget at
  /// paragraph breaks gives a page number that means the same thing on every
  /// device and after every accessibility setting, at the cost of the last
  /// page sometimes being short. The card scrolls, so a long paragraph still
  /// reads.
  ///
  /// A paragraph longer than the budget is left whole rather than split
  /// mid-sentence: one long page beats a sentence broken across a page turn.
  @visibleForTesting
  static List<String> paginate(String? text, {int budget = 900}) {
    final source = text?.trim();
    if (source == null || source.isEmpty) return const [];

    final paragraphs = source
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (paragraphs.isEmpty) return [source];

    final pages = <String>[];
    final buffer = StringBuffer();

    for (final paragraph in paragraphs) {
      if (buffer.isNotEmpty && buffer.length + paragraph.length > budget) {
        pages.add(buffer.toString().trim());
        buffer.clear();
      }
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write(paragraph);
    }
    if (buffer.isNotEmpty) pages.add(buffer.toString().trim());

    return pages;
  }
}
