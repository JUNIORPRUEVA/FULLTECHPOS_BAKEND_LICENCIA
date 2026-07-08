import 'package:flutter/widgets.dart';

/// Modelo de datos para una acción del menú de tres puntos
class AppShellAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const AppShellAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}

class AppShellActionsController extends ChangeNotifier {
  List<AppShellAction> _actions = const [];
  bool _disposed = false;
  bool _notifyScheduled = false;

  List<AppShellAction> get actions => _actions;

  void setActions(List<AppShellAction> actions) {
    _actions = List.unmodifiable(actions);
    _scheduleNotify();
  }

  void clear() {
    if (_actions.isEmpty) return;
    _actions = const [];
    _scheduleNotify();
  }

  void _scheduleNotify() {
    if (_disposed || _notifyScheduled) return;
    _notifyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      if (_disposed) return;
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

class AppShellActionsScope extends InheritedWidget {
  final AppShellActionsController controller;

  const AppShellActionsScope({
    super.key,
    required this.controller,
    required super.child,
  });

  static AppShellActionsController? maybeOf(BuildContext context) {
    final element = context
        .getElementForInheritedWidgetOfExactType<AppShellActionsScope>();
    final widget = element?.widget;
    return widget is AppShellActionsScope ? widget.controller : null;
  }

  @override
  bool updateShouldNotify(AppShellActionsScope oldWidget) {
    return oldWidget.controller != controller;
  }
}
