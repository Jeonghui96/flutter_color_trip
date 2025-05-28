import 'package:flutter/material.dart';

class NotificationProvider with ChangeNotifier {
  bool _isEnabled = true;

  bool get isEnabled => _isEnabled;

  void toggle(bool value) {
    _isEnabled = value;
    notifyListeners();
  }
}
