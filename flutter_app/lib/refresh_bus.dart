import 'package:flutter/widgets.dart';

/// App-wide data-refresh bus.
///
/// Pages subscribe via [AppRefreshListener] and silently reload their data
/// whenever [requestRefresh] fires — currently on tab switches inside the
/// [HomeShell] and when the app returns from the background.
class AppRefresh extends ChangeNotifier {
  AppRefresh._();

  static final AppRefresh instance = AppRefresh._();

  int _generation = 0;

  /// Monotonic counter of refresh requests (useful for debugging/coalescing).
  int get generation => _generation;

  void requestRefresh() {
    _generation++;
    notifyListeners();
  }
}

/// Mixin for page states that should reload on app-wide refresh signals.
///
/// Chains through the host's existing initState/dispose via super calls, so
/// adding it to a State class requires only the `with` clause and an
/// [onAppRefresh] override.
mixin AppRefreshListener<T extends StatefulWidget> on State<T> {
  /// Called when a refresh is requested. Implementations must be safe to run
  /// while the page is offstage (guard with `mounted` before setState).
  void onAppRefresh();

  void _handleAppRefresh() {
    if (mounted) onAppRefresh();
  }

  @override
  void initState() {
    super.initState();
    AppRefresh.instance.addListener(_handleAppRefresh);
  }

  @override
  void dispose() {
    AppRefresh.instance.removeListener(_handleAppRefresh);
    super.dispose();
  }
}
