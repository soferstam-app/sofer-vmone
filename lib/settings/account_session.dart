import 'package:flutter/widgets.dart';

class AccountSession extends InheritedWidget {
  const AccountSession({
    super.key,
    required this.signOut,
    this.linkPhone,
    this.managePassword,
    required super.child,
  });

  final Future<void> Function() signOut;
  final VoidCallback? linkPhone;
  final VoidCallback? managePassword;

  static AccountSession? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AccountSession>();

  @override
  bool updateShouldNotify(AccountSession oldWidget) =>
      signOut != oldWidget.signOut ||
      linkPhone != oldWidget.linkPhone ||
      managePassword != oldWidget.managePassword;
}
