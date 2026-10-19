import 'package:freezed_annotation/freezed_annotation.dart';

part 'provider_folder.freezed.dart';

/// A candidate folder on screen 3K.
///
/// The counts are the whole point of the screen — "412 FILES · 8.2 GB" is what
/// makes "Photos backup, 8,914 files" an obviously different decision from
/// "Contracts, 412 files".
@freezed
abstract class ProviderFolder with _$ProviderFolder {
  const factory ProviderFolder({
    required String id,
    required String name,
    @Default('') String path,
    @Default(0) int fileCount,
    @Default(0) int bytes,
  }) = _ProviderFolder;
}
