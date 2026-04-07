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
    return PrinterConfig(
      isEnabled: map['isEnabled'] ?? true,
      type: AppPrinterType.values[map['type'] ?? 2],
      networkIp: map['networkIp'] ?? "",
      bluetoothDevice: map['bluetoothDevice'] != null ? PrinterDevice(
        name: map['bluetoothDevice']['name'] ?? '',
        address: map['bluetoothDevice']['address'] ?? '',
      ) : null,
      paperWidth: map['paperWidth'] ?? 80,
      isKot: map['isKot'] ?? false,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory PrinterConfig.fromJson(String source) => PrinterConfig.fromMap(jsonDecode(source));
}
