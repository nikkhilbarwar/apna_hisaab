import 'dart:convert';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';

enum AppPrinterType { bluetooth, network, pdf }

class PrinterConfig {
  bool isEnabled;
  AppPrinterType type;
  String networkIp;
  PrinterDevice? bluetoothDevice;
  int paperWidth; // 58 or 80
  bool isKot; // To distinguish between Bill and KOT

  PrinterConfig({
    this.isEnabled = true,
    this.type = AppPrinterType.pdf,
    this.networkIp = "",
    this.bluetoothDevice,
    this.paperWidth = 80,
    this.isKot = false,
  });

  Map<String, dynamic> toMap() {
    return {
      'isEnabled': isEnabled,
      'type': type.index,
      'networkIp': networkIp,
      'bluetoothDevice': bluetoothDevice != null ? {
        'name': bluetoothDevice!.name,
        'address': bluetoothDevice!.address,
      } : null,
      'paperWidth': paperWidth,
      'isKot': isKot,
    };
  }

  factory PrinterConfig.fromMap(Map<String, dynamic> map) {
    bool toBool(dynamic value, {bool defaultValue = false}) {
      if (value == null) return defaultValue;
      if (value is bool) return value;
      if (value is num) return value != 0;
      if (value is String) {
        final lower = value.toLowerCase();
        return lower == 'true' || lower == '1' || lower == 'yes';
      }
      return defaultValue;
    }

    return PrinterConfig(
      isEnabled: toBool(map['isEnabled'], defaultValue: true),
      type: AppPrinterType.values[(map['type'] as num? ?? 2).toInt()],
      networkIp: map['networkIp']?.toString() ?? "",
      bluetoothDevice: map['bluetoothDevice'] != null ? PrinterDevice(
        name: map['bluetoothDevice']['name']?.toString() ?? '',
        address: map['bluetoothDevice']['address']?.toString() ?? '',
      ) : null,
      paperWidth: (map['paperWidth'] as num? ?? 80).toInt(),
      isKot: toBool(map['isKot']),
    );
  }

  String toJson() => jsonEncode(toMap());

  factory PrinterConfig.fromJson(String source) => PrinterConfig.fromMap(jsonDecode(source));
}
