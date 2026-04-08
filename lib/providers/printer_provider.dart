import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/printer_config.dart';

class PrinterProvider with ChangeNotifier {
  PrinterConfig _billPrinter = PrinterConfig(isKot: false);
  PrinterConfig _kotPrinter = PrinterConfig(isKot: true);

  PrinterConfig get billPrinter => _billPrinter;
  PrinterConfig get kotPrinter => _kotPrinter;

  PrinterProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    String? billJson = prefs.getString('bill_printer_config');
    if (billJson != null) {
      _billPrinter = PrinterConfig.fromJson(billJson);
    }

    String? kotJson = prefs.getString('kot_printer_config');
    if (kotJson != null) {
      _kotPrinter = PrinterConfig.fromJson(kotJson);
    }
    
    notifyListeners();
  }

  Future<void> updateBillPrinter(PrinterConfig config) async {
    _billPrinter = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('bill_printer_config', config.toJson());
    notifyListeners();
  }

  Future<void> updateKotPrinter(PrinterConfig config) async {
    _kotPrinter = config;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('kot_printer_config', config.toJson());
    notifyListeners();
  }

  Future<void> togglePrinter(bool isKot, bool enabled) async {
    if (isKot) {
      _kotPrinter.isEnabled = enabled;
      await updateKotPrinter(_kotPrinter);
    } else {
      _billPrinter.isEnabled = enabled;
      await updateBillPrinter(_billPrinter);
    }
  }
}
