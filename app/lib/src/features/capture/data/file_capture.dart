import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;

import '../../../core/error/app_exception.dart';
import '../../../core/logging/app_logger.dart';

/// A file chosen on the device, uploaded and ready to be a memory.
typedef UploadedFile = ({
  String storagePath,
  String filename,
  String mimeType,
  int bytes,

  /// Where the picker put its copy of the file on this phone.
  ///
  /// Inside the app's cache, so the OS may clear it at any time — which is
  /// why the capture flow hands it to `LocalOriginals` as soon as the memory
  /// has an id, rather than keeping this path around.
  String localPath,
});

/// Which kinds of file a capture tile offers.
enum FilePickKind { photos, documents, audio, any }

/// A file on the device, chosen but not yet uploaded.
typedef PickedImage = ({String path, String name});

/// A file on the device, chosen and measured but not yet uploaded.
///
/// The size comes with it because the Upload flow decides on it *before*
/// anything leaves the phone — a 1.2 GB video is refused at the picker, not
/// after a minute of uploading it (E2).
typedef PickedFile = ({String path, String name, int bytes});

/// One upload in flight — the thing the Indexing screen's first step watches.
///
/// A handle rather than a `Future`, because the screen needs three things a
/// future cannot give it: bytes as they go ("1.0 of 2.4 MB"), a pause when
/// the connection drops so the upload can pick up where it stopped (E5, E6),
/// and a way to abandon it (Remove).
abstract interface class UploadHandle {
  /// Bytes sent so far. Broadcast; late listeners miss earlier values.
  Stream<int> get sent;

  /// Completes when the object is in Storage. Throws an `AppException` —
  /// [CancelledException] after [cancel], [NetworkException] when the SDK
  /// gave up retrying.
  Future<UploadedFile> get done;

  Future<void> pause();
  Future<void> resume();
  Future<void> cancel();
}

/// Choosing a file on the device and handing it to the pipeline.
///
/// The upload is **transport, not storage**. It exists only to get the bytes
/// somewhere a Cloud Function can read them; the moment extraction succeeds
/// the object is deleted, and what survives is the derived index — chunks and
/// embeddings — exactly as §7 and §10 require. The original never leaves the
/// phone in any lasting sense: the picker's copy is kept on the device by
/// `LocalOriginals`, which is what lets the user open and share it later.
///
/// Two consequences worth knowing:
///
/// * A re-index cannot re-read the file. The extracted text lives on in the
///   chunks, so re-embedding is possible; re-*extracting* is not, and needs
///   the user to pick the file again.
/// * A failed extraction keeps its upload, or the failure would become
///   permanent the instant the bytes went.
abstract interface class FileCapture {
  /// Mirrors `storage.rules`. Checked on the phone too, so the user gets a
  /// sheet instead of a rejected upload — the rule is still what enforces
  /// it, since a client check is a courtesy, not a control.
  ///
  /// The design writes 50 MB. The rules say 100, and the copy is generated
  /// from this constant, so the screen can never promise a limit the backend
  /// does not keep.
  static const maxBytes = 100 * 1024 * 1024;

  /// Opens the system picker and measures what came back. Nothing uploads.
  ///
  /// An empty list means the user backed out, which is an ordinary decision
  /// and not an error.
  ///
  /// **The system picker, not a file browser.** An iOS app cannot list
  /// documents outside its own sandbox; `UIDocumentPicker` is the only way
  /// in. So the browsing belongs to the OS, and what Hawk owns is what
  /// happens after the choice.
  Future<List<PickedFile>> pick(FilePickKind kind);

  /// Photos chosen through the system photo picker, measured.
  ///
  /// The picker, not an in-app roll. An in-app roll means asking to read
  /// *every* photo on the phone; the system picker (PHPicker on iOS, the
  /// photo picker on Android) asks for no permission at all and hands back
  /// only what the user chose. For an app whose pitch is that the vault is
  /// yours, the smaller ask is the right one — and it is why the design's
  /// "photo access is off" sheet (E9) never has a reason to appear here.
  Future<List<PickedFile>> pickImages();

  /// One photo from the camera, or null if the user backed out.
  Future<PickedImage?> takePhoto();

  /// Uploads files already on the device, all at once, with no progress.
  /// Skips any that fail validation rather than failing the batch.
  ///
  /// The home screen's camera uses this; the Library uses [upload], which
  /// reports as it goes.
  Future<List<UploadedFile>> uploadPaths(List<PickedImage> files);

  /// Starts uploading [file] and returns at once.
  UploadHandle upload(PickedFile file);

  /// SHA-256 of the file's bytes, hex. What "already in your Library" (E4)
  /// compares, so a renamed copy is still recognised and an edited file with
  /// the same name is not.
  Future<String> fingerprint(String path);

  /// A paper document, scanned, as **one PDF**.
  ///
  /// The scanning UI is the platform's own — VisionKit on iOS, ML Kit's
  /// document scanner on Android — which is what the design's F5·3 and F5·4
  /// draw: live edge detection, auto-capture, page review, Done. It cannot
  /// be skinned, and it does the edge-finding and de-skew.
  ///
  /// One PDF rather than an image per page: a five-page contract is one
  /// memory, so a question about it comes back as one result that can be
  /// opened, not five fragments in no particular order. Null when the user
  /// backed out. Throws [CameraDeniedException] when the camera is off.
  Future<PickedFile?> scanDocument();
}

/// The camera permission is off — the one thing a scan cannot route around.
///
/// Its own type rather than a `badRequest` with a sentence in it, because the
/// Library answers it with a sheet that can open Settings (E9's shape), not
/// with a line of text.
class CameraDeniedException implements Exception {
  const CameraDeniedException();
}

@LazySingleton(as: FileCapture)
class DeviceFileCapture implements FileCapture {
  DeviceFileCapture(this._storage, this._auth, this._logger);

  final FirebaseStorage _storage;
  final fb.FirebaseAuth _auth;
  final AppLogger _logger;

  /// Owned, not injected — the same arrangement as the speech plugin. It is a
  /// thin handle on platform channels with nothing worth faking separately:
  /// tests replace [FileCapture] as a whole.
  final ImagePicker _images = ImagePicker();

  @override
  Future<List<PickedFile>> pick(FilePickKind kind) async {
    // Bytes are deliberately not requested — a 90 MB PDF held in memory on a
    // mid-range phone is an out-of-memory kill, and `putFile` streams from
    // disk instead.
    final picked = await FilePicker.pickFiles(type: _typeFor(kind));
    return [
      for (final one in picked)
        if (one.path case final path?)
          (path: path, name: one.name, bytes: await one.length()),
    ];
  }

  @override
  Future<List<PickedFile>> pickImages() async {
    final picked = await _images.pickMultiImage(
      // Full resolution: this is read for its text, and downscaling a photo
      // of a page is how small print stops being readable.
      requestFullMetadata: false,
    );
    return [
      for (final x in picked)
        (path: x.path, name: x.name, bytes: await x.length()),
    ];
  }

  @override
  Future<PickedImage?> takePhoto() async {
    final shot = await _images.pickImage(
      source: ImageSource.camera,
      requestFullMetadata: false,
    );
    return shot == null ? null : (path: shot.path, name: shot.name);
  }

  @override
  Future<PickedFile?> scanDocument() async {
    final List<String>? result;
    try {
      result = await CunningDocumentScanner.getPictures(
        scannerSource: ScannerSource.camera,
        asPdf: true,
      );
    } on CunningDocumentScannerException catch (error) {
      if (error.code == 'permission_denied') {
        throw const CameraDeniedException();
      }
      rethrow;
    }
    final path = result?.firstOrNull;
    if (path == null) return null;
    return (
      path: path,
      name: scanName(DateTime.now()),
      bytes: await File(path).length(),
    );
  }

  /// "Scan 23 Sep 2026 14.05.pdf" — the plugin names its file with a random
  /// id, and that id would become the memory's title in the library.
  @visibleForTesting
  static String scanName(DateTime at) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Scan ${at.day} ${months[at.month - 1]} ${at.year} '
        '${two(at.hour)}.${two(at.minute)}.pdf';
  }

  @override
  Future<List<UploadedFile>> uploadPaths(List<PickedImage> files) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) throw const AppException.unauthorized();
    final out = <UploadedFile>[];
    for (final f in files) {
      try {
        out.add(await _uploadNow(uid, File(f.path), f.name));
      } on AppException catch (error) {
        _logger.warning(
          'Skipped a file in a batch',
          name: 'capture',
          data: {'file': f.name, 'error': error.toString()},
        );
      }
    }
    return out;
  }

  @override
  UploadHandle upload(PickedFile file) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return _FailedUpload(const AppException.unauthorized());
    }
    final mime = mimeTypeFor(file.name);
    final storagePath = _storagePathFor(uid, file.name);
    final task = _storage
        .ref(storagePath)
        .putFile(File(file.path), _metadata(mime, file.name));

    return _StorageUpload(task, (
      storagePath: storagePath,
      filename: file.name,
      mimeType: mime,
      bytes: file.bytes,
      localPath: file.path,
    ), _logger);
  }

  @override
  Future<String> fingerprint(String path) =>
      // Off the UI isolate: hashing 100 MB is a few hundred milliseconds of
      // solid CPU, which on the main isolate is the type sheet freezing
      // mid-dismiss.
      Isolate.run(
        () async => (await sha256.bind(File(path).openRead()).first).toString(),
      );

  FileType _typeFor(FilePickKind kind) => switch (kind) {
    FilePickKind.photos => FileType.image,
    FilePickKind.audio => FileType.audio,
    // Everything, not just the types Hawk reads. The OS picker greys out
    // what a filter excludes and says nothing about why; letting the file
    // through and answering "Can't read .pages files — export it as PDF"
    // (E3) is the same refusal with a way forward in it.
    FilePickKind.documents || FilePickKind.any => FileType.any,
  };

  /// Validate, upload, describe — all at once, for [uploadPaths].
  Future<UploadedFile> _uploadNow(String uid, File file, String name) async {
    final size = await file.length();
    if (size > FileCapture.maxBytes) {
      throw AppException.badRequest(
        message:
            '$name is ${(size / (1024 * 1024)).round()} MB. '
            'The limit is ${FileCapture.maxBytes ~/ (1024 * 1024)} MB.',
      );
    }
    if (size == 0) {
      throw AppException.badRequest(message: '$name is empty.');
    }

    final mime = mimeTypeFor(name);
    final storagePath = _storagePathFor(uid, name);

    try {
      await _storage.ref(storagePath).putFile(file, _metadata(mime, name));
    } on FirebaseException catch (error, stackTrace) {
      _logger.warning(
        'Upload failed',
        name: 'capture',
        data: {'code': error.code},
      );
      throw mapStorageError(error, stackTrace);
    }

    return (
      storagePath: storagePath,
      filename: name,
      mimeType: mime,
      bytes: size,
      localPath: file.path,
    );
  }

  /// Per-user because `storage.rules` scopes access by the uid segment —
  /// anything outside `users/{uid}/` is denied to everybody. `captures/`
  /// should normally be empty: an object lingering there is either an
  /// extraction still in flight or one that failed and is awaiting retry.
  static String _storagePathFor(String uid, String name) =>
      'users/$uid/captures/${DateTime.now().microsecondsSinceEpoch}-'
      '${_safeName(name)}';

  static SettableMetadata _metadata(String mime, String name) =>
      SettableMetadata(
        contentType: mime,
        // Kept so a later re-index can name the file the user chose, rather
        // than the timestamped path.
        customMetadata: {'originalName': name},
      );

  static AppException mapStorageError(
    FirebaseException error,
    StackTrace stackTrace,
  ) => switch (error.code) {
    'unauthorized' => const AppException.unauthorized(),
    'canceled' => const AppException.cancelled(),
    'retry-limit-exceeded' => const AppException.network(),
    _ => AppException.unknown(cause: error, stackTrace: stackTrace),
  };

  /// `storage.rules` matches on content type, so an unknown type would be
  /// rejected at the door. Derived from the extension because the picker does
  /// not report a mime type on every platform.
  static String mimeTypeFor(String filename) {
    final ext = p.extension(filename).toLowerCase().replaceFirst('.', '');
    return switch (ext) {
      'pdf' => 'application/pdf',
      'png' => 'image/png',
      'jpg' || 'jpeg' => 'image/jpeg',
      'heic' || 'heif' => 'image/heic',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      'mp3' => 'audio/mpeg',
      'm4a' || 'aac' => 'audio/mp4',
      'wav' => 'audio/wav',
      'ogg' || 'opus' => 'audio/ogg',
      'txt' || 'md' || 'markdown' => 'text/plain',
      'csv' => 'text/csv',
      'rtf' => 'text/rtf',
      // Falls back to plain text rather than octet-stream: the rules reject
      // octet-stream, and an unknown extension is far more often text than
      // not. A genuinely binary file then fails extraction, visibly.
      _ => 'text/plain',
    };
  }

  /// Strips anything that would change the meaning of a Storage path.
  static String _safeName(String name) =>
      name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
}

/// A Storage upload, seen through [UploadHandle].
class _StorageUpload implements UploadHandle {
  _StorageUpload(this._task, this._result, this._logger) {
    // Listened to once, here, and re-broadcast: the SDK's stream is
    // single-subscription on some platforms, and the Indexing screen and the
    // island can both be watching.
    _snapshots = _task.snapshotEvents.listen(
      (snapshot) => _sent.add(snapshot.bytesTransferred),
      // The task's future carries the error; the stream's copy is noise.
      onError: (Object _) {},
    );
  }

  final UploadTask _task;
  final UploadedFile _result;
  final AppLogger _logger;
  final _sent = StreamController<int>.broadcast();
  late final StreamSubscription<TaskSnapshot> _snapshots;

  @override
  Stream<int> get sent => _sent.stream;

  @override
  late final Future<UploadedFile> done = _finish();

  Future<UploadedFile> _finish() async {
    try {
      await _task;
      return _result;
    } on FirebaseException catch (error, stackTrace) {
      _logger.warning(
        'Upload failed',
        name: 'capture',
        data: {'code': error.code},
      );
      throw DeviceFileCapture.mapStorageError(error, stackTrace);
    } finally {
      await _snapshots.cancel();
      await _sent.close();
    }
  }

  // Each returns false when the task is not in a state that allows it —
  // pausing a finished upload, say. That is not worth reporting.
  @override
  Future<void> pause() => _task.pause();

  @override
  Future<void> resume() => _task.resume();

  @override
  Future<void> cancel() => _task.cancel();
}

/// An upload that could not start. Fails the moment anyone looks.
class _FailedUpload implements UploadHandle {
  _FailedUpload(this._error);

  final AppException _error;

  @override
  Stream<int> get sent => const Stream.empty();

  @override
  Future<UploadedFile> get done => Future.error(_error);

  @override
  Future<void> pause() async {}

  @override
  Future<void> resume() async {}

  @override
  Future<void> cancel() async {}
}
