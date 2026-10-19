import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import '../../domain/entities/auth_session.dart';
import '../../domain/repositories/auth_repository.dart';

/// Mirrors the repository's session into the widget tree.
///
/// It holds no logic of its own on purpose — the repository is the authority,
/// and this exists so the router and the UI can watch it without every screen
/// subscribing to a raw stream.
@lazySingleton
class SessionCubit extends Cubit<AuthStatus> {
  SessionCubit(this._repository) : super(_repository.current) {
    _subscription = _repository.status.listen(emit);
  }

  final AuthRepository _repository;
  late final StreamSubscription<AuthStatus> _subscription;

  Future<void> signOut() => _repository.signOut();

  @override
  Future<void> close() {
    _subscription.cancel();
    return super.close();
  }
}
