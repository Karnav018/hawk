import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/widgets.dart';
import 'package:injectable/injectable.dart';
import 'package:open_file/open_file.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../logging/app_logger.dart';
import 'local_originals.dart';

/// Where a memory's original can be reached from this phone.
///
/// Four cases, tried in this order, and the order is the design:
///
/// 1. [OriginalOnDevice] — the file itself, already on this phone. First
///    because it is instant, works offline, and costs no data.
/// 2. [OriginalInVault] — kept in Firebase Storage. This is what makes the
///    product a vault rather than an index: a file captured on a phone that
///    was since lost, or on a laptop, is still here. Fetched on demand and
///    then cached as case 1, so it is downloaded once.
/// 3. [OriginalAtUrl] — a link, or a Drive file. Opened externally, so a
///    Drive link lands in the Drive app rather than a browser tab.
/// 4. [OriginalUnavailable] — nothing reachable: a note, or a file the plan's
///    allowance could not keep. Said plainly rather than hidden.
sealed class OriginalHandle {
  const OriginalHandle();
}

final class OriginalOnDevice extends OriginalHandle {
  const OriginalOnDevice(this.file);
  final File file;
}

final class OriginalInVault extends OriginalHandle {
  const OriginalInVault({required this.storagePath, required this.filename});
  final String storagePath;
  final String filename;
}

final class OriginalAtUrl extends OriginalHandle {
  const OriginalAtUrl(this.uri);
  final Uri uri;
}

final class OriginalUnavailable extends OriginalHandle {
  const OriginalUnavailable();
}

/// What happened when the user asked to open something.
enum OpenOutcome {
  opened,

  /// The file is fine; nothing installed can show it.
  noApp,

  /// It is in the vault but this phone could not fetch it — offline, most
  /// likely. Distinct from [failed] because waiting fixes it.
  unreachable,

  /// The kept file has gone since it was found — cleared by the user through
  /// system settings, most likely.
  missing,

  /// Nothing to open: see [OriginalUnavailable].
  unavailable,

  failed,
}

/// Opening and sharing a memory's original with the phone's own apps.
abstract interface class OriginalAccess {
  Future<OriginalHandle> resolve({
    required String memoryId,
    String? url,
    String? storagePath,
    String? filename,
  });

  Future<OpenOutcome> open(OriginalHandle handle);

  /// Shares the file, the link, or — when neither is reachable — [fallback],
  /// which callers set to what the app does know: the title and the passage
  /// that matched. Returns false only when there was nothing at all to share.
  ///
  /// Fetches a vault file to this phone and returns it as a device handle.
  /// Returns the original handle unchanged for every other case.
  Future<OriginalHandle> materialise(OriginalHandle handle, String memoryId);

  /// [origin] anchors the share sheet on iPad, where UIKit throws without one.
  Future<bool> share(
    OriginalHandle handle, {
    required String title,
    String? fallback,
    Rect? origin,
  });
}

@LazySingleton(as: OriginalAccess)
class NativeOriginalAccess implements OriginalAccess {
  NativeOriginalAccess(this._originals, this._storage, this._logger);

  final LocalOriginals _originals;
  final FirebaseStorage _storage;
  final AppLogger _logger;

  @override
  Future<OriginalHandle> resolve({
    required String memoryId,
    String? url,
    String? storagePath,
    String? filename,
  }) async {
    final file = await _originals.find(memoryId);
    if (file != null) return OriginalOnDevice(file);

    final kept = (storagePath ?? '').trim();
    if (kept.isNotEmpty) {
      return OriginalInVault(
        storagePath: kept,
        filename: filename?.trim().isNotEmpty ?? false
            ? filename!.trim()
            : kept.split('/').last,
      );
    }

    final uri = Uri.tryParse((url ?? '').trim());
    // Only http(s): a memory's `url` is user- or connector-supplied data, and
    // handing an arbitrary scheme to the OS is how an app ends up launching
    // something nobody meant it to.
    if (uri != null && (uri.scheme == 'https' || uri.scheme == 'http')) {
      return OriginalAtUrl(uri);
    }
    return const OriginalUnavailable();
  }

  /// Brings a vault file down to this phone, into the same cache a captured
  /// file uses — so the second open is instant and offline.
  ///
  /// Returns null when the fetch fails. Read through the Storage SDK rather
  /// than a signed URL, so `storage.rules` is what grants the read and no
  /// shareable link to the file is ever minted.
  Future<File?> _fetch(OriginalInVault handle, String memoryId) async {
    try {
      final target = await _originals.destination(
        memoryId: memoryId,
        filename: handle.filename,
      );
      await _storage.ref(handle.storagePath).writeToFile(target);
      return target;
    } on Object catch (error) {
      _logger.warning(
        'Could not fetch the kept file',
        name: 'files',
        data: {'path': handle.storagePath, 'error': error.toString()},
      );
      return null;
    }
  }

  @override
  Future<OpenOutcome> open(OriginalHandle handle) async {
    switch (handle) {
      case OriginalOnDevice(:final file):
        if (!file.existsSync()) return OpenOutcome.missing;
        // `open_file`, not `open_filex`: the fork has had no release since
        // March 2025 and never adopted Swift Package Manager, which Flutter
        // 3.47 warns will become a build error. The original is maintained
        // again, ships a Package.swift, and no longer declares the media
        // permissions that made the fork necessary.
        final result = await OpenFile.open(file.path);
        return switch (result.type) {
          ResultType.done => OpenOutcome.opened,
          ResultType.noAppToOpen => OpenOutcome.noApp,
          ResultType.fileNotFound => OpenOutcome.missing,
          _ => OpenOutcome.failed,
        };
      case OriginalInVault():
        // Resolved with the memory id it belongs to; `openOriginal` fetches
        // first and reopens as a device file, so reaching here means the
        // fetch was skipped.
        return OpenOutcome.unreachable;
      case OriginalAtUrl(:final uri):
        final opened = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        return opened ? OpenOutcome.opened : OpenOutcome.noApp;
      case OriginalUnavailable():
        return OpenOutcome.unavailable;
    }
  }

  @override
  Future<OriginalHandle> materialise(
    OriginalHandle handle,
    String memoryId,
  ) async {
    if (handle is! OriginalInVault) return handle;
    final file = await _fetch(handle, memoryId);
    return file == null ? handle : OriginalOnDevice(file);
  }

  @override
  Future<bool> share(
    OriginalHandle handle, {
    required String title,
    String? fallback,
    Rect? origin,
  }) async {
    final ShareParams params;
    switch (handle) {
      case OriginalOnDevice(:final file) when file.existsSync():
        params = ShareParams(
          files: [XFile(file.path)],
          subject: title,
          sharePositionOrigin: origin,
        );
      case OriginalAtUrl(:final uri):
        // `uri` alone: share_plus throws if `uri` and `text` are both set.
        params = ShareParams(
          uri: uri,
          subject: title,
          sharePositionOrigin: origin,
        );
      default:
        final text = [title, fallback]
            .whereType<String>()
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .join('\n\n');
        // Empty `text` also throws; with nothing to say, share nothing.
        if (text.isEmpty) return false;
        params = ShareParams(
          text: text,
          subject: title,
          sharePositionOrigin: origin,
        );
    }
    await SharePlus.instance.share(params);
    return true;
  }
}
