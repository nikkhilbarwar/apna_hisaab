import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';

enum AppPrinterType { bluetooth, network, pdf }

class PrinterProvider with ChangeNotifier {
  AppPrinterType _selectedType = AppPrinterType.pdf;
  String _networkIp = "";
  PrinterDevice? _selectedBluetoothDevice;
  int _paperWidth = 80; 
  
  AppPrinterType get selectedType => _selectedType;
  String get networkIp => _networkIp;
  PrinterDevice? get selectedBluetoothDevice => _selectedBluetoothDevice;
  int get paperWidth => _paperWidth;

  PrinterProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    int typeIndex = prefs.getInt('printer_type') ?? 2; 
    _selectedType = AppPrinterType.values[typeIndex];
    _networkIp = prefs.getString('printer_ip') ?? "";
    _paperWidth = prefs.getInt('paper_width') ?? 80;
    
    String? btJson = prefs.getString('selected_bt_device');
    if (btJson != null) {
      try {
        Map<String, dynamic> map = jsonDecode(btJson);
        _selectedBluetoothDevice = PrinterDevice(
          name: map['name'] ?? '',
          address: map['address'] ?? '',
        );
      } catch (_) {}
    }
    notifyListeners();
  }

  Future<void> setPrinterType(AppPrinterType type) async {
    _selectedType = type;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('printer_type', type.index);
    notifyListeners();
  }

  Future<void> setPaperWidth(int width) async {
    _paperWidth = width;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('paper_width', width);
    notifyListeners();
  }

  Future<void> setNetworkIp(String ip) async {
    _networkIp = ip;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('printer_ip', ip);
    notifyListeners();
  }

  Future<void> setBluetoothDevice(PrinterDevice? device) async {
    _selectedBluetoothDevice = device;
    final prefs = await SharedPreferences.getInstance();
    if (device != null) {
      await prefs.setString('selected_bt_device', jsonEncode({
        'name': device.name,
        'address': device.address,
      }));
    } else {
      await prefs.remove('selected_bt_device');
    }
    notifyListeners();
  }
}
