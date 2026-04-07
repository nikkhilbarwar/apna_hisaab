import 'package:flutter/material.dart';
import 'package:flutter_pos_printer_platform_image_3/flutter_pos_printer_platform_image_3.dart';
import 'package:provider/provider.dart';
import '../../providers/printer_provider.dart';
import '../../providers/profile_provider.dart';
import '../../models/printer_config.dart';

class PrinterSettingsScreen extends StatefulWidget {
  const PrinterSettingsScreen({super.key});

  @override
  State<PrinterSettingsScreen> createState() => _PrinterSettingsScreenState();
}

class _PrinterSettingsScreenState extends State<PrinterSettingsScreen> with SingleTickerProviderStateMixin {
  final PrinterManager _printerManager = PrinterManager.instance;
  List<PrinterDevice> _devices = [];
  bool _isScanning = false;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  void _scan() async {
    setState(() {
      _isScanning = true;
      _devices = [];
    });
    
    _printerManager.discovery(type: PrinterType.bluetooth, isBle: false).listen((device) {
      setState(() {
        if (!_devices.any((d) => d.address == device.address)) {
          _devices.add(device);
        }
      });
    });

    Future.delayed(const Duration(seconds: 5), () {
      if (mounted) setState(() => _isScanning = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final printerProv = Provider.of<PrinterProvider>(context);
    final profile = Provider.of<ProfileProvider>(context);

    return Scaffold(
      backgroundColor: profile.scaffoldColor,
      appBar: AppBar(
        title: const Text("Printer Settings", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: profile.cardColor,
        elevation: 0,
        foregroundColor: profile.textColor,
        bottom: TabBar(
          controller: _tabController,
          labelColor: profile.themeColor,
          unselectedLabelColor: profile.secondaryTextColor,
          indicatorColor: profile.themeColor,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: "BILL PRINTER", icon: Icon(Icons.receipt_long)),
            Tab(text: "KOT PRINTER", icon: Icon(Icons.restaurant_menu)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPrinterTab(printerProv.billPrinter, printerProv, profile, false),
          _buildPrinterTab(printerProv.kotPrinter, printerProv, profile, true),
        ],
      ),
      bottomNavigationBar: _isScanning 
        ? LinearProgressIndicator(color: profile.themeColor, backgroundColor: profile.themeColor.withOpacity(0.1))
        : null,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _scan,
        label: Text(_isScanning ? "Scanning..." : "Scan Bluetooth"),
        icon: _isScanning 
          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
          : const Icon(Icons.bluetooth_searching),
        backgroundColor: profile.themeColor,
      ),
    );
  }

  Widget _buildPrinterTab(PrinterConfig config, PrinterProvider prov, ProfileProvider profile, bool isKot) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Main Switch Card
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: profile.cardColor,
              borderRadius: BorderRadius.circular(16),
              boxShadow: profile.themeShadow,
              border: Border.all(color: profile.themeColor.withOpacity(0.2)),
            ),
            child: SwitchListTile(
              secondary: Icon(isKot ? Icons.kitchen : Icons.receipt, color: config.isEnabled ? profile.themeColor : profile.secondaryTextColor),
              title: Text(isKot ? "Kitchen Printer" : "Billing Printer", style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(config.isEnabled ? "Active and ready" : "Currently disabled"),
              value: config.isEnabled,
              activeColor: profile.themeColor,
              onChanged: (val) {
                config.isEnabled = val;
                isKot ? prov.updateKotPrinter(config) : prov.updateBillPrinter(config);
              },
            ),
          ),
          
          if (config.isEnabled) ...[
            const SizedBox(height: 20),
            _buildSectionHeader(profile, "CONFIGURATION"),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: profile.cardColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: profile.themeShadow,
                border: Border.all(color: profile.themeColor.withOpacity(0.1)),
              ),
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.settings_input_component),
                    title: const Text("Connection Type"),
                    trailing: DropdownButton<AppPrinterType>(
                      value: config.type,
                      underline: const SizedBox(),
                      dropdownColor: profile.cardColor,
                      items: AppPrinterType.values.map((t) => DropdownMenuItem(value: t, child: Text(t.name.toUpperCase()))).toList(),
                      onChanged: (t) {
                        if (t != null) {
                          config.type = t;
                          isKot ? prov.updateKotPrinter(config) : prov.updateBillPrinter(config);
                        }
                      },
                    ),
                  ),
                  const Divider(height: 1),
                  if (config.type == AppPrinterType.network)
                    ListTile(
                      leading: const Icon(Icons.lan),
                      title: const Text("IP Address"),
                      trailing: SizedBox(
                        width: 150,
                        child: TextField(
                          textAlign: TextAlign.end,
                          decoration: const InputDecoration(hintText: "192.168.1.100", border: InputBorder.none),
                          onChanged: (val) {
                            config.networkIp = val;
                            isKot ? prov.updateKotPrinter(config) : prov.updateBillPrinter(config);
                          },
                        ),
                      ),
                    )
                  else if (config.type == AppPrinterType.bluetooth)
                    ListTile(
                      leading: const Icon(Icons.bluetooth),
                      title: const Text("Bluetooth Device"),
                      subtitle: Text(config.bluetoothDevice?.name ?? "Select from list below"),
                      trailing: Icon(Icons.circle, color: config.bluetoothDevice != null ? Colors.green : Colors.grey, size: 12),
                    ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.straighten),
                    title: const Text("Paper Size"),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [58, 80].map((w) => Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: ChoiceChip(
                          label: Text("${w}mm"),
                          selected: config.paperWidth == w,
                          selectedColor: profile.themeColor,
                          labelStyle: TextStyle(color: config.paperWidth == w ? Colors.white : profile.textColor),
                          onSelected: (val) {
                            if (val) {
                              config.paperWidth = w;
                              isKot ? prov.updateKotPrinter(config) : prov.updateBillPrinter(config);
                            }
                          },
                        ),
                      )).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ],

          if (config.isEnabled && config.type == AppPrinterType.bluetooth) ...[
            const SizedBox(height: 24),
            _buildSectionHeader(profile, "AVAILABLE BLUETOOTH DEVICES"),
            const SizedBox(height: 10),
            if (_devices.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(30),
                decoration: BoxDecoration(
                  color: profile.cardColor.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: profile.secondaryTextColor.withOpacity(0.1)),
                ),
                child: Column(
                  children: [
                    Icon(Icons.bluetooth_searching, size: 40, color: profile.secondaryTextColor.withOpacity(0.5)),
                    const SizedBox(height: 10),
                    Text("No devices found. Tap 'Scan Bluetooth'.", style: TextStyle(color: profile.secondaryTextColor)),
                  ],
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _devices.length,
                separatorBuilder: (c, i) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final d = _devices[index];
                  bool isSelected = config.bluetoothDevice?.address == d.address;
                  return Card(
                    elevation: 0,
                    color: isSelected ? profile.themeColor.withOpacity(0.1) : profile.cardColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: isSelected ? profile.themeColor : Colors.transparent),
                    ),
                    child: ListTile(
                      leading: Icon(Icons.print, color: isSelected ? profile.themeColor : profile.secondaryTextColor),
                      title: Text(d.name, style: TextStyle(fontWeight: FontWeight.bold, color: isSelected ? profile.themeColor : profile.textColor)),
                      subtitle: Text(d.address ?? 'No address', style: TextStyle(fontSize: 12, color: profile.secondaryTextColor)),
                      trailing: isSelected ? Icon(Icons.check_circle, color: profile.themeColor) : null,
                      onTap: () {
                        config.bluetoothDevice = d;
                        isKot ? prov.updateKotPrinter(config) : prov.updateBillPrinter(config);
                      },
                    ),
                  );
                },
              ),
          ],
          
          if (!isKot) ...[
            const SizedBox(height: 24),
            _buildSectionHeader(profile, "AUTOMATION"),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: profile.cardColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: profile.themeShadow,
                border: Border.all(color: profile.themeColor.withOpacity(0.2)),
              ),
              child: SwitchListTile(
                title: const Text("Auto Print on Checkout"),
                subtitle: const Text("Print bill as soon as you save transaction"),
                value: profile.isAutoPrintEnabled,
                activeColor: profile.themeColor,
                onChanged: (val) => profile.toggleAutoPrint(val),
              ),
            ),
          ],
          const SizedBox(height: 80), // Space for FAB
        ],
      ),
    );
  }

  Widget _buildSectionHeader(ProfileProvider profile, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title, 
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: profile.secondaryTextColor, letterSpacing: 1.1)
      ),
    );
  }
}
