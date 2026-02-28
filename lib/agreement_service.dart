import 'package:shared_preferences/shared_preferences.dart';

class AgreementService {
  static const String _keyAccepted = 'no_warranty_accepted';

  static Future<bool> hasAccepted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_keyAccepted) ?? false;
  }

  static Future<void> accept() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAccepted, true);
  }
}
