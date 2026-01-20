import 'package:shared_preferences/shared_preferences.dart';

class FinanceService {
  static const String _linkedIncomeKey = 'linked_income_amount';

  static Future<double> getLinkedIncome() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_linkedIncomeKey) ?? 0.0;
  }

  static Future<void> setLinkedIncome(double value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_linkedIncomeKey, value);
  }
}












