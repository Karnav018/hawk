import 'package:freezed_annotation/freezed_annotation.dart';

import '../../domain/entities/memory.dart';
import '../../domain/entities/memory_enums.dart';

part 'memory_dto.freezed.dart';
part 'memory_dto.g.dart';

/// Wire format, mirroring the backend's `MemoryOut` exactly.
///
/// Enums arrive as raw strings and are parsed leniently: a backend that adds a
/// new memory type should not crash an older client (see `MemoryType.parse`).
@freezed
abstract class MemoryDto with _$MemoryDto {
  const factory MemoryDto({
    required String id,
    required String type,
    required String status,
    @JsonKey(name: 'created_at') required DateTime createdAt,
    String? title,
    String? description,
    String? text,
    String? language,
    @Default(0.0) double importance,
    SourceDto? source,
    @Default(<TopicDto>[]) List<TopicDto> topics,
    @Default(<EntityDto>[]) List<EntityDto> entities,
  }) = _MemoryDto;

  const MemoryDto._();

  factory MemoryDto.fromJson(Map<String, dynamic> json) =>
      _$MemoryDtoFromJson(json);

  Memory toEntity() => Memory(
    id: id,
    type: MemoryType.parse(type),
    status: ProcessingStatus.parse(status),
    createdAt: createdAt,
    title: title,
    description: description,
    text: text,
    language: language,
    importance: importance,
    source: source?.toEntity(),
    topics: topics.map((t) => t.toEntity()).toList(),
    entities: entities.map((e) => e.toEntity()).toList(),
  );
}

@freezed
abstract class SourceDto with _$SourceDto {
  const factory SourceDto({
    required String id,
    required String provider,
    String? url,
    String? filename,
    @JsonKey(name: 'mime_type') String? mimeType,
    @JsonKey(name: 'size_bytes') int? sizeBytes,
    @JsonKey(name: 'captured_at') DateTime? capturedAt,
  }) = _SourceDto;

  const SourceDto._();

  factory SourceDto.fromJson(Map<String, dynamic> json) =>
      _$SourceDtoFromJson(json);

  Source toEntity() => Source(
    id: id,
    provider: StorageProvider.parse(provider),
    url: url,
    filename: filename,
    mimeType: mimeType,
    sizeBytes: sizeBytes,
    capturedAt: capturedAt,
  );
}

@freezed
abstract class TopicDto with _$TopicDto {
  const factory TopicDto({
    required String id,
    required String name,
    required String slug,
    @JsonKey(name: 'memory_count') @Default(0) int memoryCount,
  }) = _TopicDto;

  const TopicDto._();

  factory TopicDto.fromJson(Map<String, dynamic> json) =>
      _$TopicDtoFromJson(json);

  Topic toEntity() =>
      Topic(id: id, name: name, slug: slug, memoryCount: memoryCount);
}

@freezed
abstract class EntityDto with _$EntityDto {
  const factory EntityDto({
    required String id,
    required String name,
    required String slug,
    @Default('thing') String kind,
    @JsonKey(name: 'memory_count') @Default(0) int memoryCount,
  }) = _EntityDto;

  const EntityDto._();

  factory EntityDto.fromJson(Map<String, dynamic> json) =>
      _$EntityDtoFromJson(json);

  NamedEntity toEntity() => NamedEntity(
    id: id,
    name: name,
    slug: slug,
    kind: kind,
    memoryCount: memoryCount,
  );
}

/// The backend's generic `Page[T]` envelope.
@freezed
abstract class MemoryPageDto with _$MemoryPageDto {
  const factory MemoryPageDto({
    required List<MemoryDto> items,
    required int total,
    required int limit,
    required int offset,
  }) = _MemoryPageDto;

  factory MemoryPageDto.fromJson(Map<String, dynamic> json) =>
      _$MemoryPageDtoFromJson(json);
}
