# Knowra — Flutter + BLoC Architecture

## 1. Architecture Goal

Knowra is a local-first personal memory/search application.

The architecture is intentionally simple:

- **Flutter** for the mobile application
- **BLoC/Cubit** for state management
- **Clean Architecture + Feature-first structure**
- **Firebase** for authentication, user metadata, plans, quota, account lifecycle, and backend services
- **On-device RAG** for indexing and fast memory search
- **Google Drive** as an external source
- **Phone storage** as an external source
- A single **Library** for uploading, indexing, browsing, and opening files
- A single **SearchBloc** shared by Voice and Chat search
- Only **Home** and **Library** in bottom navigation
- **Profile** is accessed from Home, not bottom navigation

---

# 2. Product Principles

The product should remain simple.

### Home

Home is for searching memory.

Two possible home experiences:

```text
Voice-first user
        ↓
     Voice Orb
        ↓
      Search

Chat-first user
        ↓
      Chat UI
        ↓
      Search
```

### Library

Library is for:

- Uploading
- Indexing
- Viewing files
- Managing indexed data
- Browsing Google Drive
- Indexing Google Drive files

### Profile

Profile is for:

- User information
- Plan
- Remaining quota
- Account actions
- Sign out
- Deactivate account
- Delete account

---

# 3. High-Level Architecture

```text
                         ┌──────────────────────┐
                         │     KNOWRA APP       │
                         │       Flutter        │
                         └──────────┬───────────┘
                                    │
              ┌─────────────────────┼─────────────────────┐
              │                     │                     │
              ▼                     ▼                     ▼
        ┌───────────┐        ┌─────────────┐       ┌─────────────┐
        │   Home    │        │   Library   │       │   Profile   │
        │  Search   │        │ Upload/View │       │  Account    │
        └─────┬─────┘        └──────┬──────┘       └──────┬──────┘
              │                     │                     │
              └─────────────────────┼─────────────────────┘
                                    ▼
                         ┌─────────────────────┐
                         │    BLoC / Cubit     │
                         │                     │
                         │ Auth                │
                         │ Onboarding          │
                         │ Home                │
                         │ Search              │
                         │ Library             │
                         │ Indexing            │
                         │ Drive               │
                         │ Profile             │
                         │ Viewer              │
                         └─────────┬───────────┘
                                   │
                              Use Cases
                                   │
                              Repositories
                                   │
                 ┌─────────────────┼─────────────────┐
                 │                 │                 │
                 ▼                 ▼                 ▼
          ┌────────────┐    ┌─────────────┐   ┌──────────────┐
          │ Local RAG  │    │ Firebase    │   │ External     │
          │ Engine     │    │             │   │ Sources      │
          │            │    │ Auth        │   │              │
          │ Extract    │    │ Firestore   │   │ Google Drive │
          │ Chunk      │    │ Functions   │   │ Phone Vault  │
          │ Embeddings │    │ Storage     │   │ Camera       │
          │ Vector DB  │    │             │   │ Microphone   │
          └────────────┘    └─────────────┘   └──────────────┘
```

---

# 4. Core Architectural Principle

Knowra has two different types of data:

```text
                    KNOWRA
                       │
          ┌────────────┴────────────┐
          │                         │
          ▼                         ▼
       SOURCE                    INDEX
          │                         │
          ▼                         ▼
    Actual user file          Knowra metadata
                              + chunks
                              + embeddings
```

## Phone file

```text
Phone owns the actual file
Knowra owns the index
```

## Google Drive file

```text
Google Drive owns the actual file
Knowra owns the index
```

Deleting an index must never delete the original source file.

```text
Delete Knowra Index
        ↓
Original File Remains
```

---

# 5. Firebase Responsibilities

Firebase is the backend, but Firebase should **not** be the primary vector-search engine.

Firebase responsibilities:

```text
Firebase
│
├── Firebase Authentication
│   ├── Google Sign In
│   └── Email Authentication
│
├── Firestore
│   ├── User metadata
│   ├── Profile
│   ├── Plan
│   ├── Usage
│   ├── File metadata
│   ├── Drive connection metadata
│   └── Settings
│
├── Cloud Functions
│   ├── Quota validation
│   ├── Plan validation
│   ├── Account deletion
│   ├── Account deactivation
│   └── Subscription/billing operations
│
└── Firebase Storage
    └── Only for data that actually needs cloud storage
```

The RAG search remains primarily local:

```text
Device
│
├── Source references
├── Extracted text
├── Chunks
├── Embeddings
└── Vector database
```

---

# 6. Flutter Architecture

Use:

> **Feature-first + Clean Architecture + BLoC**

The architecture is:

```text
Presentation
      ↓
BLoC / Cubit
      ↓
Use Cases
      ↓
Repository Interfaces
      ↓
Repository Implementations
      ↓
Data Sources / Services
```

---

# 7. Project Structure

```text
lib/
│
├── main.dart
│
├── app/
│   ├── app.dart
│   ├── router/
│   │   └── app_router.dart
│   └── theme/
│       ├── app_theme.dart
│       ├── app_colors.dart
│       └── app_text_styles.dart
│
├── core/
│   ├── constants/
│   ├── errors/
│   ├── extensions/
│   ├── utils/
│   ├── services/
│   │   ├── permission_service.dart
│   │   ├── file_service.dart
│   │   ├── connectivity_service.dart
│   │   └── logger_service.dart
│   └── dependency_injection/
│       └── injection.dart
│
├── features/
│
│   ├── auth/
│   │   ├── data/
│   │   │   ├── datasources/
│   │   │   ├── models/
│   │   │   └── repositories/
│   │   ├── domain/
│   │   │   ├── entities/
│   │   │   ├── repositories/
│   │   │   └── usecases/
│   │   └── presentation/
│   │       ├── bloc/
│   │       ├── screens/
│   │       └── widgets/
│   │
│   ├── onboarding/
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │       ├── bloc/
│   │       ├── screens/
│   │       └── widgets/
│   │
│   ├── home/
│   │   ├── domain/
│   │   └── presentation/
│   │       ├── bloc/
│   │       ├── screens/
│   │       └── widgets/
│   │
│   ├── search/
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │       ├── bloc/
│   │       ├── screens/
│   │       └── widgets/
│   │
│   ├── library/
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │       ├── bloc/
│   │       ├── screens/
│   │       └── widgets/
│   │
│   ├── indexing/
│   │   ├── data/
│   │   ├── domain/
│   │   ├── services/
│   │   └── presentation/
│   │       └── bloc/
│   │
│   ├── drive/
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   │       ├── bloc/
│   │       ├── screens/
│   │       └── widgets/
│   │
│   ├── viewer/
│   │   ├── domain/
│   │   └── presentation/
│   │       ├── cubit/
│   │       ├── screens/
│   │       └── widgets/
│   │
│   └── profile/
│       ├── data/
│       ├── domain/
│       └── presentation/
│           ├── bloc/
│           ├── screens/
│           └── widgets/
```

---

# 8. Navigation Architecture

Bottom navigation contains only:

```text
┌──────────────────────────────────────┐
│                                      │
│              Screen                  │
│                                      │
├──────────────────────────────────────┤
│                                      │
│       Home                 Library   │
│        ●                      ○      │
└──────────────────────────────────────┘
```

Profile is not part of bottom navigation.

```text
Home
  │
  └── Profile
```

---

# 9. Complete Navigation Flow

```text
                         ┌──────────────┐
                         │    Splash    │
                         └──────┬───────┘
                                │
                                ▼
                         ┌──────────────┐
                         │ Auth Check   │
                         └──────┬───────┘
                                │
                    ┌───────────┴───────────┐
                    │                       │
                    ▼                       ▼
               Logged Out               Logged In
                    │                       │
                    ▼                       ▼
                  Auth                   Home
                    │
          ┌─────────┴─────────┐
          │                   │
          ▼                   ▼
     Continue Google     Continue Email
          │                   │
          ▼                   ▼
    Google Sign In       Enter Email
          │                   │
          └─────────┬─────────┘
                    ▼
              User Setup
                    │
                    ▼
              Search Mode
                    │
              ┌─────┴─────┐
              │           │
            Voice        Chat
              │           │
              └─────┬─────┘
                    ▼
            Bring Storage
                    │
          ┌─────────┴─────────┐
          │                   │
          ▼                   ▼
     Google Drive        Phone Vault
          │                   │
          └─────────┬─────────┘
                    ▼
                   Home
```

---

# 10. Returning User Flow

```text
Splash
   ↓
Firebase Auth Check
   ↓
Authenticated?
   │
   ├── NO  → Auth Screen
   │
   └── YES
          ↓
        Home
```

If onboarding is incomplete:

```text
Auth
 ↓
Onboarding
 ↓
Home
```

---

# 11. Onboarding BLoC

The onboarding process should be represented by one BLoC.

## OnboardingBloc

Responsibilities:

```text
OnboardingBloc
│
├── Load onboarding state
├── Set user information
├── Set search mode
├── Connect Google Drive
├── Enable phone vault
└── Complete onboarding
```

Events:

```dart
abstract class OnboardingEvent {}

class LoadOnboarding extends OnboardingEvent {}

class SetSearchMode extends OnboardingEvent {
  final SearchMode mode;
}

class ConnectDrive extends OnboardingEvent {}

class EnablePhoneVault extends OnboardingEvent {}

class CompleteOnboarding extends OnboardingEvent {}
```

State:

```dart
class OnboardingState {
  final String? userName;
  final SearchMode searchMode;
  final bool driveConnected;
  final bool phoneVaultEnabled;
  final bool completed;
  final bool loading;
  final String? error;
}
```

Search mode:

```dart
enum SearchMode {
  voice,
  chat,
}
```

---

# 12. Auth Architecture

```text
Auth Screen
     │
     ├───────────────┐
     │               │
     ▼               ▼
Google            Email
     │               │
     ▼               ▼
Firebase Auth    Firebase Auth
     │               │
     └───────┬───────┘
             ▼
         AuthBloc
             │
             ▼
          Router
             │
             ▼
        Onboarding/Home
```

## AuthBloc

```text
AuthBloc
│
├── CheckAuthStatus
├── SignInWithGoogle
├── SignInWithEmail
├── SignOut
└── DeleteAccount
```

States:

```text
Initial
Loading
Authenticated
Unauthenticated
Error
```

---

# 13. Home Architecture

Home should remain simple.

```text
Home
│
├── Profile Button
│
├── Voice-first UI
│   └── Orb
│
└── Chat-first UI
    └── Chat
```

The search logic does not belong in HomeBloc.

```text
Home
 │
 ├── Voice UI
 │      └── SearchBloc
 │
 └── Chat UI
        └── SearchBloc
```

## HomeBloc

Keep it minimal:

```text
HomeBloc
│
├── LoadHome
└── ChangeHomeMode
```

The persisted primary search mode comes from onboarding/user settings.

---

# 14. Voice Search Flow

```text
              ┌──────────────┐
              │     Home     │
              └──────┬───────┘
                     │
                     ▼
                Voice Orb
                     │
                     ▼
              Microphone
                     │
                     ▼
            Speech-to-Text
                     │
                     ▼
             Search Query
                     │
                     ▼
               SearchBloc
                     │
                     ▼
             SearchUseCase
                     │
                     ▼
            Local RAG Engine
                     │
                     ▼
              Search Results
                     │
                     ▼
             Result Screen
                     │
                     ▼
                  Viewer
```

---

# 15. Chat Search Flow

```text
Home
 │
 ▼
Chat
 │
 ▼
User Query
 │
 ▼
SearchBloc
 │
 ▼
SearchUseCase
 │
 ▼
Local RAG Engine
 │
 ▼
Search Results
 │
 ▼
Chat Result
 │
 ▼
Viewer
```

Voice and Chat use the **same SearchBloc and SearchUseCase**.

```text
                SearchBloc
                /        \
             Voice       Chat
                \        /
                 \      /
                  ▼    ▼
                SearchUseCase
                     │
                     ▼
               Local RAG
```

---

# 16. SearchBloc

## Events

```dart
abstract class SearchEvent {}

class SearchSubmitted extends SearchEvent {
  final String query;
}

class VoiceQueryReceived extends SearchEvent {
  final String query;
}

class SearchCleared extends SearchEvent {}

class NextResult extends SearchEvent {}

class PreviousResult extends SearchEvent {}
```

## States

```text
Initial
Listening
Processing
Searching
Results
NoResults
Error
```

Conceptually:

```dart
class SearchState {
  final String? query;
  final List<SearchResult> results;
  final int currentIndex;
  final SearchStatus status;
  final String? error;
}
```

---

# 17. Search Result UI

The result should contain only what the user needs.

```text
┌────────────────────────────────────┐
│                                    │
│ Short answer / description         │
│                                    │
│ ┌────────────────────────────────┐ │
│ │ 📄 ProjectProposal.pdf         │ │
│ │ Documents / Projects           │ │
│ │                                │ │
│ │           Open File →          │ │
│ └────────────────────────────────┘ │
│                                    │
└────────────────────────────────────┘
```

Do not show:

- RAG details
- Vector similarity
- Index location
- Technical metadata
- Embedding information
- Unnecessary source information
- Internal processing information

The user sees:

```text
Short answer
+
File
+
Device location
+
Open
```

---

# 18. Multiple Search Results

Use a stacked result interaction.

```text
        ┌──────────────────────────┐
        │ File 1                   │
        │ ProjectProposal.pdf      │
        │ Documents/Projects       │
        └──────────────────────────┘
                   ▲
                   │
        ┌──────────────────────────┐
        │ File 2                   │
        │ ProposalFinal.pdf        │
        │ Downloads/               │
        └──────────────────────────┘
                   ▲
                   │
        ┌──────────────────────────┐
        │ File 3                   │
        │ Project.pdf              │
        │ Drive/Projects           │
        └──────────────────────────┘
```

User can:

```text
Drag / Swipe
      ↓
Next result
```

---

# 19. Search Domain Model

```dart
class SearchQuery {
  final String text;
  final SearchMode mode;
}

class SearchResult {
  final String fileId;
  final String title;
  final String description;
  final String location;
  final FileSource source;
}
```

File source:

```dart
enum FileSource {
  phone,
  drive,
  camera,
  scan,
  audio,
  link,
}
```

---

# 20. Library Architecture

Library is the central data-management screen.

```text
                    LIBRARY
                       │
       ┌───────────────┼────────────────┐
       │               │                │
       ▼               ▼                ▼
     Upload           Files            Drive
       │
       ├── Files
       ├── Images
       ├── Links
       ├── Scan
       ├── Audio
       └── Speak
```

Remove:

```text
Write a Note
```

completely.

---

# 21. Library UI

```text
┌──────────────────────────────────────┐
│ Library                         🔍   │
├──────────────────────────────────────┤
│                                      │
│ Quick Add                            │
│                                      │
│ ┌──────┐ ┌──────┐ ┌──────┐          │
│ │ 📄   │ │ 🖼   │ │ 🔗   │          │
│ │Files │ │Images│ │Links │          │
│ └──────┘ └──────┘ └──────┘          │
│                                      │
│ ┌──────┐ ┌──────┐ ┌──────┐          │
│ │ 📷   │ │ 🎵   │ │ 🎙   │          │
│ │ Scan │ │Audio │ │Speak │          │
│ └──────┘ └──────┘ └──────┘          │
│                                      │
├──────────────────────────────────────┤
│ Recent                               │
│                                      │
│ 📄 Resume.pdf                        │
│    Indexed · Today                   │
│                                      │
│ 🖼 project.png                       │
│    Indexing · Today                  │
│                                      │
│ 🎵 Meeting.mp3                       │
│    Indexed · Yesterday               │
│                                      │
├──────────────────────────────────────┤
│ Home                    Library      │
└──────────────────────────────────────┘
```

---

# 22. Upload Categories

There are exactly six upload categories:

```text
Files
Images
Links
Scan
Audio
Speak
```

## Files

- Open device file picker
- Multi-select
- Register selected files
- Index

## Images

- Select multiple images
- Capture a new photo
- Register image
- OCR/extract if required
- Index

## Links

- Enter public URL
- Fetch public content
- Extract text
- Chunk
- Embed
- Index

## Scan

- Open camera
- Scan document
- Save document
- OCR
- Index

## Audio

- Select audio from device
- Transcribe
- Chunk
- Embed
- Index

## Speak

- Open microphone
- Record speech
- Speech-to-text
- Save as memory
- Index

---

# 23. LibraryBloc

Responsibilities:

```text
LibraryBloc
│
├── LoadFiles
├── RefreshFiles
├── OpenFile
├── DeleteIndex
└── FilterFiles
```

The actual indexing work belongs to `IndexingBloc`.

---

# 24. Indexing Architecture

All upload types converge into one indexing pipeline.

```text
Files ────────┐
Images ───────┤
Links ────────┤
Scan ─────────┤
Audio ────────┤
Speak ────────┘
               │
               ▼
       Source Registration
               │
               ▼
       Content Extraction
               │
               ▼
          Text Generation
               │
               ▼
             Chunk
               │
               ▼
           Embedding
               │
               ▼
         Local Vector DB
               │
               ▼
        Status = INDEXED
```

---

# 25. IndexingBloc

Events:

```dart
abstract class IndexingEvent {}

class StartIndexing extends IndexingEvent {}

class IndexFile extends IndexingEvent {
  final String fileId;
}

class IndexImage extends IndexingEvent {
  final String fileId;
}

class IndexLink extends IndexingEvent {
  final String url;
}

class IndexAudio extends IndexingEvent {
  final String fileId;
}

class IndexScan extends IndexingEvent {
  final String fileId;
}

class IndexDriveFile extends IndexingEvent {
  final String fileId;
}

class RetryIndexing extends IndexingEvent {
  final String fileId;
}

class RemoveIndex extends IndexingEvent {
  final String fileId;
}
```

States:

```text
Idle
Extracting
Processing
Embedding
Completed
Failed
```

---

# 26. IndexingBloc Rule

Do not put extraction, chunking, or embedding implementation directly inside the BLoC.

Bad:

```dart
class IndexingBloc {
  extractPdf();
  chunkText();
  generateEmbedding();
  saveVector();
}
```

Correct:

```text
IndexingBloc
      │
      ▼
IndexFileUseCase
      │
      ▼
IndexingRepository
      │
      ├── ContentExtractor
      ├── ChunkingService
      ├── EmbeddingService
      └── VectorStore
```

BLoC coordinates state.

Services perform work.

---

# 27. Local RAG Architecture

```text
                ┌────────────────────┐
                │     FILE SOURCE    │
                └─────────┬──────────┘
                          │
                          ▼
                ┌────────────────────┐
                │ Content Extractor  │
                │                    │
                │ PDF                │
                │ DOCX               │
                │ TXT                │
                │ Image → OCR        │
                │ Audio → STT        │
                │ URL → Web text     │
                └─────────┬──────────┘
                          │
                          ▼
                ┌────────────────────┐
                │ Text Normalizer    │
                └─────────┬──────────┘
                          │
                          ▼
                ┌────────────────────┐
                │ Chunker            │
                └─────────┬──────────┘
                          │
                          ▼
                ┌────────────────────┐
                │ Embedding Service  │
                └─────────┬──────────┘
                          │
                          ▼
                ┌────────────────────┐
                │ Local Vector DB    │
                └────────────────────┘
```

---

# 28. Local Search Pipeline

```text
User Query
    │
    ▼
Query Processing
    │
    ▼
Query Embedding
    │
    ▼
Local Vector Search
    │
    ▼
Top-K Chunks
    │
    ▼
Group Chunks by File
    │
    ▼
Resolve File Metadata
    │
    ▼
SearchResult
```

---

# 29. Indexing Service

Recommended interface:

```dart
abstract class IndexingService {
  Future<IndexResult> indexFile(FileRecord file);

  Future<void> removeIndex(String fileId);

  Future<void> reindex(String fileId);

  Future<IndexStatus> getStatus(String fileId);
}
```

The implementation can internally use:

```text
IndexingService
│
├── DocumentExtractor
├── ImageExtractor
├── OCRService
├── AudioTranscriber
├── WebExtractor
├── ChunkingService
├── EmbeddingService
└── VectorStore
```

---

# 30. File Data Model

```dart
class FileRecord {
  final String id;
  final String name;
  final String mimeType;
  final FileSource source;
  final String sourceId;
  final String? localPath;
  final String location;
  final int size;
  final DateTime createdAt;
  final DateTime modifiedAt;
  final DateTime? indexedAt;
  final IndexStatus indexStatus;
}
```

Index status:

```dart
enum IndexStatus {
  pending,
  indexing,
  indexed,
  failed,
}
```

---

# 31. Chunk Data Model

```dart
class ChunkRecord {
  final String id;
  final String fileId;
  final String text;
  final int chunkIndex;
  final int? pageNumber;
  final DateTime createdAt;
}
```

Embedding metadata:

```text
Embedding
│
├── chunkId
├── vector
└── modelVersion
```

The exact storage representation depends on the selected local vector database.

---

# 32. Google Drive Architecture

Google Drive should be treated as a source connector.

```text
                    GOOGLE DRIVE
                         │
                         │ OAuth
                         ▼
                ┌──────────────────┐
                │ Drive Connector  │
                └────────┬─────────┘
                         │
              ┌──────────┴──────────┐
              │                     │
              ▼                     ▼
        Browse Files            Index File
              │                     │
              │                     ▼
              │               Read/Download
              │                     │
              │                     ▼
              │                Local RAG
              │
              ▼
         Open File
```

Important:

> Drive access and Drive indexing are separate operations.

The user can browse Drive without indexing everything.

---

# 33. Drive Rules

Users can:

```text
Browse Drive
Open Drive file
Index Drive file
Remove Knowra index
Re-index Drive file
```

Users cannot:

```text
Delete original Drive file from Knowra
```

The action should be:

```text
Remove from Knowra
```

not:

```text
Delete from Drive
```

---

# 34. Drive UI

```text
┌──────────────────────────────────────┐
│ Library                              │
│                                      │
│ [ My Files ]       [ Drive ]        │
├──────────────────────────────────────┤
│                                      │
│ Google Drive                         │
│                                      │
│ 📁 Projects                          │
│ 📄 Resume.pdf                        │
│ 📄 Research.pdf                      │
│                                      │
│ 📄 Research.pdf                      │
│    ✓ Indexed                         │
│                                      │
│    Open                              │
│    Re-index                          │
│    Remove from Knowra                │
│                                      │
└──────────────────────────────────────┘
```

---

# 35. DriveBloc

Responsibilities:

```text
DriveBloc
│
├── ConnectDrive
├── DisconnectDrive
├── LoadDriveFiles
├── RefreshDrive
├── OpenDriveFile
├── IndexDriveFile
└── RemoveIndex
```

Do not duplicate the indexing implementation in DriveBloc.

```text
DriveBloc
     │
     ▼
DriveRepository
     │
     ├── Browse
     ├── Open
     └── Read
             │
             ▼
      IndexFileUseCase
             │
             ▼
        Local RAG
```

---

# 36. File Viewer Architecture

All files should be openable.

The viewer should not care where the file came from.

```text
Search Result
     │
     ▼
FileViewer
     │
     ├── Phone File
     ├── Drive File
     ├── Uploaded File
     ├── Image
     ├── PDF
     ├── Text
     └── Audio
```

Use a unified interface:

```dart
FileViewer(
  file: fileRecord,
);
```

Viewer resolution:

```text
FileRecord
     │
     ▼
FileViewerCubit
     │
     ├── Resolve source
     ├── Resolve path/URL
     └── Load preview
```

---

# 37. ViewerCubit

Viewer state is simple enough for Cubit.

```text
ViewerCubit
│
├── OpenFile
├── LoadFile
└── CloseViewer
```

States:

```text
Initial
Loading
Loaded
Error
```

---

# 38. Profile Architecture

Profile remains intentionally small.

```text
┌──────────────────────────────────┐
│ Profile                          │
├──────────────────────────────────┤
│                                  │
│          👤                      │
│       User Name                  │
│                                  │
│       Pro Plan                   │
│                                  │
├──────────────────────────────────┤
│ Storage / Memory                 │
│                                  │
│ ███████████░░░░                  │
│                                  │
│ 6.2 GB / 10 GB                   │
│                                  │
├──────────────────────────────────┤
│ Account                          │
│                                  │
│ Deactivate Account               │
│ Sign Out                         │
│ Delete Account                   │
│                                  │
└──────────────────────────────────┘
```

---

# 39. ProfileBloc

Responsibilities:

```text
ProfileBloc
│
├── LoadProfile
├── LoadPlan
├── LoadUsage
├── SignOut
├── DeactivateAccount
└── DeleteAccount
```

---

# 40. Plan Architecture

Do not hardcode plan rules into screens.

```text
Plan
│
├── planId
├── storageLimit
├── memoryLimit
├── indexedFileLimit
└── features
```

Example:

```json
{
  "planId": "pro",
  "storageLimit": 10737418240,
  "memoryRetention": 30,
  "maxIndexedFiles": 1000
}
```

The UI consumes plan state from the backend.

---

# 41. Firestore Structure

Recommended starting structure:

```text
users/
  {userId}/
    profile
    settings
    plan
    usage

    files/
      {fileId}

    connections/
      {connectionId}
```

Example user:

```json
{
  "name": "User Name",
  "email": "user@example.com",
  "searchMode": "voice",
  "onboardingCompleted": true,
  "createdAt": "timestamp",
  "updatedAt": "timestamp"
}
```

Example file:

```json
{
  "name": "ProjectProposal.pdf",
  "mimeType": "application/pdf",
  "source": "phone",
  "sourceId": "...",
  "location": "Documents/Projects/",
  "size": 2450000,
  "indexStatus": "indexed",
  "indexedAt": "timestamp",
  "createdAt": "timestamp",
  "modifiedAt": "timestamp"
}
```

Drive file:

```json
{
  "name": "Research.pdf",
  "source": "google_drive",
  "sourceId": "drive-file-id",
  "mimeType": "application/pdf",
  "indexStatus": "indexed"
}
```

---

# 42. Account Lifecycle

## Sign Out

```text
Profile
   ↓
Sign Out
   ↓
Firebase Auth Sign Out
   ↓
Auth Screen
```

## Deactivate

```text
Profile
   ↓
Deactivate Account
   ↓
Confirmation
   ↓
deactivated = true
   ↓
Restrict account access
```

## Delete

```text
Profile
   ↓
Delete Account
   ↓
Confirmation
   ↓
Delete Firebase Auth
   ↓
Delete Firestore data
   ↓
Delete backend data
   ↓
Delete local index
```

Deletion must be treated as a destructive operation.

---

# 43. Local Storage Ownership

Recommended conceptual separation:

```text
Device
│
├── Original Files
│
└── Knowra Data
    │
    ├── File Metadata
    ├── Extracted Text
    ├── Chunks
    └── Embeddings / Vector Index
```

Google Drive:

```text
Google Drive
│
└── Original File

Device
│
└── Knowra Index
```

---

# 44. BLoC Dependency Diagram

```text
                         UI
                          │
        ┌─────────────────┼─────────────────┐
        │                 │                 │
        ▼                 ▼                 ▼
     AuthBloc         SearchBloc        LibraryBloc
        │                 │                 │
        ▼                 ▼                 ▼
  AuthUseCases       SearchUseCase      LibraryUseCases
        │                 │                 │
        ▼                 ▼                 ▼
 AuthRepository     SearchRepository   LibraryRepository
        │                 │                 │
        ▼                 ▼                 ▼
   Firebase        Local RAG Engine    Local/Firebase
```

Indexing:

```text
                    LibraryBloc
                         │
                         ▼
                   IndexingBloc
                         │
                         ▼
                 IndexFileUseCase
                         │
          ┌──────────────┼───────────────┐
          ▼              ▼               ▼
      Extractor       Chunker       Embedding
          │              │               │
          └──────────────┴───────────────┘
                         │
                         ▼
                    VectorStore
```

---

# 45. Complete BLoC Map

```text
AuthBloc
│
├── Authentication
└── Account session


OnboardingBloc
│
├── User setup
├── Search mode
└── Storage setup


HomeBloc
│
└── Home state


SearchBloc
│
├── Voice search
├── Chat search
├── Search results
└── Result navigation


LibraryBloc
│
├── Files
├── Recent items
└── Index status


IndexingBloc
│
├── File indexing
├── Image indexing
├── Link indexing
├── Scan indexing
├── Audio indexing
├── Speak indexing
└── Drive indexing


DriveBloc
│
├── OAuth connection
├── Drive browsing
├── Drive file opening
└── Drive refresh


ViewerCubit
│
└── File opening/viewing


ProfileBloc
│
├── Profile
├── Plan
├── Usage
├── Sign out
├── Deactivate
└── Delete
```

---

# 46. Recommended BLoC Communication

Avoid BLoC-to-BLoC coupling wherever possible.

Bad:

```text
SearchBloc → LibraryBloc → DriveBloc → IndexingBloc
```

Prefer:

```text
UI
 │
 ▼
BLoC
 │
 ▼
Use Case
 │
 ▼
Repository
 │
 ▼
Service
```

If multiple parts need the same operation, they should call the same use case/repository.

Example:

```text
Library
    │
    └── Index File
             │
             ▼
       IndexFileUseCase
             ▲
             │
Drive ───────┘
```

---

# 47. Recommended Domain Use Cases

## Auth

```text
CheckAuthStatus
SignInWithGoogle
SignInWithEmail
SignOut
DeleteAccount
```

## Onboarding

```text
LoadOnboarding
SaveSearchMode
ConnectStorage
CompleteOnboarding
```

## Search

```text
SearchMemory
ResolveSearchResult
```

## Library

```text
GetFiles
GetFile
DeleteIndex
RefreshLibrary
```

## Indexing

```text
IndexFile
IndexImage
IndexLink
IndexAudio
IndexScan
IndexDriveFile
ReindexFile
RemoveIndex
```

## Drive

```text
ConnectDrive
GetDriveFiles
OpenDriveFile
RefreshDrive
```

## Profile

```text
GetProfile
GetPlan
GetUsage
DeactivateAccount
SignOut
DeleteAccount
```

---

# 48. Repository Interfaces

Example:

```dart
abstract class SearchRepository {
  Future<List<SearchResult>> search(String query);
}
```

```dart
abstract class LibraryRepository {
  Future<List<FileRecord>> getFiles();

  Future<FileRecord?> getFile(String id);

  Future<void> deleteIndex(String fileId);
}
```

```dart
abstract class DriveRepository {
  Future<void> connect();

  Future<List<FileRecord>> getFiles();

  Future<FileRecord?> getFile(String id);

  Future<void> refresh();
}
```

```dart
abstract class IndexingRepository {
  Future<IndexResult> indexFile(FileRecord file);

  Future<void> removeIndex(String fileId);

  Future<void> reindex(String fileId);
}
```

---

# 49. Main Application State Flow

```text
                 App Start
                    │
                    ▼
                 AuthBloc
                    │
           ┌────────┴────────┐
           │                 │
        Logged Out       Logged In
           │                 │
           ▼                 ▼
          Auth         Onboarding Check
                              │
                    ┌─────────┴─────────┐
                    │                   │
                Incomplete           Complete
                    │                   │
                    ▼                   ▼
               Onboarding             Home
                                        │
                              ┌─────────┴─────────┐
                              │                   │
                            Search             Library
                              │                   │
                       SearchBloc            LibraryBloc
                              │                   │
                              │              IndexingBloc
                              │                   │
                              ▼                   ▼
                          Results              Viewer
```

---

# 50. End-to-End Voice Flow

```text
User
 │
 ▼
Home
 │
 ▼
Orb
 │
 ▼
Microphone Permission
 │
 ▼
Speech Recognition
 │
 ▼
VoiceQueryReceived
 │
 ▼
SearchBloc
 │
 ▼
SearchMemoryUseCase
 │
 ▼
SearchRepository
 │
 ▼
Local Vector Store
 │
 ▼
Relevant Chunks
 │
 ▼
File Resolver
 │
 ▼
SearchResult[]
 │
 ▼
Result UI
 │
 ▼
User drags result stack
 │
 ▼
Open File
 │
 ▼
ViewerCubit
 │
 ▼
File Viewer
```

---

# 51. End-to-End Chat Flow

```text
User
 │
 ▼
Home
 │
 ▼
Chat Input
 │
 ▼
SearchSubmitted
 │
 ▼
SearchBloc
 │
 ▼
SearchMemoryUseCase
 │
 ▼
Local Search
 │
 ▼
SearchResult[]
 │
 ▼
Chat Result
 │
 ▼
Open File
 │
 ▼
Viewer
```

---

# 52. End-to-End Upload Flow

```text
User
 │
 ▼
Library
 │
 ▼
Quick Add
 │
 ├── Files
 ├── Images
 ├── Links
 ├── Scan
 ├── Audio
 └── Speak
 │
 ▼
Source Registration
 │
 ▼
FileRecord
 │
 ▼
IndexingBloc
 │
 ▼
IndexFileUseCase
 │
 ▼
Content Extraction
 │
 ▼
Text Normalization
 │
 ▼
Chunking
 │
 ▼
Embedding
 │
 ▼
Vector Store
 │
 ▼
indexStatus = indexed
 │
 ▼
LibraryBloc refresh
```

---

# 53. End-to-End Drive Flow

```text
Library
 │
 ▼
Drive Tab
 │
 ▼
DriveBloc
 │
 ▼
Google Drive OAuth
 │
 ▼
Drive File Browser
 │
 ├───────────────┐
 │               │
 ▼               ▼
Open             Index
 │               │
 ▼               ▼
Drive Viewer   IndexingBloc
                 │
                 ▼
              Local RAG
                 │
                 ▼
             Indexed File
```

---

# 54. Team Responsibilities

The architecture can be divided into teams/modules.

```text
Team A — Flutter UI
│
├── Splash
├── Auth
├── Onboarding
├── Home
├── Library
├── Search
├── Profile
└── Viewer


Team B — Local RAG
│
├── Extractors
├── OCR
├── STT
├── Chunking
├── Embeddings
├── Vector DB
└── Retrieval


Team C — Firebase
│
├── Auth
├── Firestore
├── Functions
├── Plans
├── Quota
└── Account lifecycle


Team D — Integrations
│
├── Google Drive
├── File picker
├── Camera
└── Microphone
```

---

# 55. Development Phases

## Phase 1 — Foundation

```text
Flutter project
BLoC setup
Dependency injection
Routing
Theme
Firebase setup
Authentication
```

## Phase 2 — Onboarding

```text
Splash
Google Sign In
Email Sign In
User setup
Voice/Chat selection
Storage selection
Onboarding persistence
```

## Phase 3 — Home

```text
Home
Voice Orb
Chat UI
Profile navigation
Bottom navigation
```

## Phase 4 — Library

```text
Library
Quick Add
Files
Images
Links
Scan
Audio
Speak
File list
Index status
```

## Phase 5 — Viewer

```text
PDF viewer
Image viewer
Text viewer
Audio player
Drive file viewer
```

## Phase 6 — Local RAG

```text
Extractors
OCR
STT
Chunking
Embeddings
Vector database
Retrieval
File resolution
```

## Phase 7 — Search

```text
SearchBloc
Voice search
Chat search
Result screen
Result stack
Open file
```

## Phase 8 — Google Drive

```text
OAuth
Drive browser
Drive file opening
Drive indexing
Refresh/reconnect
Remove index
```

## Phase 9 — Profile/Plans

```text
Profile
Plan
Quota
Usage
Deactivate
Sign out
Delete account
```

---

# 56. Architecture Rules for the Team

## Rule 1

UI should not directly access Firebase.

```text
Bad:

Screen → Firebase

Good:

Screen
  ↓
BLoC
  ↓
UseCase
  ↓
Repository
  ↓
Firebase
```

## Rule 2

BLoC should not contain heavy business logic.

```text
BLoC = State orchestration

UseCase = Business operation

Repository = Data abstraction

Service = Technical implementation
```

## Rule 3

Voice and Chat must share SearchBloc.

```text
Voice ──┐
        ├── SearchBloc → SearchUseCase → Local RAG
Chat ───┘
```

## Rule 4

Drive and Phone files must share the same indexing pipeline.

```text
Phone ───┐
         ├── IndexFileUseCase → Local RAG
Drive ───┘
```

## Rule 5

Deleting an index must never delete the original source file.

```text
Remove Index
     ↓
Delete chunks
     ↓
Delete embeddings
     ↓
Update metadata
     ↓
Original source remains
```

## Rule 6

Profile is not bottom navigation.

## Rule 7

Write a Note is removed.

## Rule 8

Do not expose technical RAG details to users.

---

# 57. Final Architecture Diagram

```text
┌─────────────────────────────────────────────────────────────┐
│                         KNOWRA                              │
│                     Flutter + BLoC                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌──────────┐      ┌──────────┐      ┌──────────┐          │
│  │   HOME   │      │ LIBRARY  │      │ PROFILE  │          │
│  │          │      │          │      │          │          │
│  │ Voice    │      │ Upload   │      │ User     │          │
│  │ Chat     │      │ Files    │      │ Plan     │          │
│  │ Orb      │      │ Drive    │      │ Usage    │          │
│  └────┬─────┘      │ Viewer   │      │ Account  │          │
│       │             └────┬─────┘      └────┬─────┘          │
│       │                  │                 │                │
│       ▼                  ▼                 ▼                │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                    BLoC / Cubit                      │  │
│  │                                                      │  │
│  │ AuthBloc                                             │  │
│  │ OnboardingBloc                                       │  │
│  │ HomeBloc                                             │  │
│  │ SearchBloc                                           │  │
│  │ LibraryBloc                                          │  │
│  │ IndexingBloc                                         │  │
│  │ DriveBloc                                            │  │
│  │ ProfileBloc                                          │  │
│  │ ViewerCubit                                          │  │
│  └───────────────────────┬──────────────────────────────┘  │
│                          │                                 │
│                          ▼                                 │
│                   ┌──────────────┐                         │
│                   │   Use Cases  │                         │
│                   └──────┬───────┘                         │
│                          │                                 │
│                          ▼                                 │
│                   ┌──────────────┐                         │
│                   │ Repositories │                         │
│                   └──────┬───────┘                         │
│                          │                                 │
├──────────────────────────┼──────────────────────────────────┤
│                          │                                 │
│             ┌────────────┴────────────┐                    │
│             │                         │                    │
│             ▼                         ▼                    │
│    ┌─────────────────┐       ┌──────────────────┐          │
│    │   LOCAL RAG     │       │     FIREBASE     │          │
│    │                 │       │                  │          │
│    │ Extract         │       │ Authentication   │          │
│    │ Normalize       │       │ Firestore        │          │
│    │ Chunk           │       │ Cloud Functions  │          │
│    │ Embed           │       │ Storage          │          │
│    │ Vector Search   │       │ Plans / Quota    │          │
│    └────────┬────────┘       └──────────────────┘          │
│             │                                               │
│             ▼                                               │
│    ┌─────────────────┐                                     │
│    │ Local Vector DB │                                     │
│    └────────┬────────┘                                     │
│             │                                               │
│             ▼                                               │
│       Fast Local Search                                    │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                     SOURCE CONNECTORS                       │
│                                                             │
│   Phone Storage │ Google Drive │ Camera │ Microphone        │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

# 58. The Simplified Mental Model

The entire Knowra architecture can be remembered as:

```text
                    KNOWRA
                       │
          ┌────────────┴────────────┐
          │                         │
        SEARCH                   LIBRARY
          │                         │
    ┌─────┴─────┐           ┌───────┴───────┐
    │           │           │               │
  Voice        Chat       Upload           Drive
    │           │           │               │
    └─────┬─────┘           └───────┬───────┘
          │                         │
          ▼                         ▼
      SearchBloc              IndexingBloc
          │                         │
          └──────────┬──────────────┘
                     ▼
                 Local RAG
                     │
                     ▼
               Vector Store
                     │
                     ▼
                File Result
                     │
                     ▼
                   Viewer


Firebase
   │
   ├── Auth
   ├── User
   ├── File Metadata
   ├── Plans
   ├── Quota
   └── Account Lifecycle
```

---

# 59. Architecture Freeze

For the first implementation, freeze the following:

```text
State Management
→ BLoC / Cubit

Architecture
→ Feature-first Clean Architecture

Backend
→ Firebase

Authentication
→ Google + Email

Bottom Navigation
→ Home + Library

Profile
→ Accessible from Home

Search
→ SearchBloc

Search Modes
→ Voice + Chat

Indexing
→ IndexingBloc

Storage Sources
→ Phone + Google Drive

RAG
→ On-device

Search
→ Local vector retrieval

Viewer
→ Unified FileViewer + ViewerCubit

Uploads
→ Files + Images + Links + Scan + Audio + Speak

Notes
→ Removed
```

The key architectural decision is:

```text
                  ┌─────────────┐
                  │ SearchBloc  │
                  └──────┬──────┘
                         │
             ┌───────────┴───────────┐
             │                       │
           Voice                    Chat
             │                       │
             └───────────┬───────────┘
                         ▼
                 SearchUseCase
                         │
                         ▼
                   Local RAG
                         │
                         ▼
                  SearchResult
                         │
                         ▼
                     Viewer
```

and:

```text
Phone / Drive / Upload
          │
          ▼
     IndexingBloc
          │
          ▼
   IndexFileUseCase
          │
          ▼
      Local RAG
          │
          ▼
     Vector Store
```

This keeps the product and engineering architecture aligned with the original requirement: **simple UI, one search system, one indexing pipeline, local-first retrieval, Firebase for backend/account responsibilities, and BLoC for Flutter state management.**
