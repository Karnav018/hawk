import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Owns the sun/moon switch that sits in the home header.
///
/// A [Cubit] rather than a full BLoC: there is exactly one input (toggle) and
/// no event payload worth modelling. Dark is the default — the design calls it
/// "DARK THEME — DEFAULT" — so an unset preference resolves to dark, never to
/// the system setting.
@lazySingleton
class ThemeCubit extends Cubit<ThemeMode> {
  ThemeCubit() : super(ThemeMode.dark);

  static const _key = 'knowra.theme_mode';

  /// Restores the stored preference. Safe to call before the first frame.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_key);
    emit(stored == ThemeMode.light.name ? ThemeMode.light : ThemeMode.dark);
  }

  Future<void> toggle() async {
    final next = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    emit(next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, next.name);
  }
}
