import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/supplier_provider.dart';
import '../../models/supplier_model.dart';
import '../../providers/profile_provider.dart';
import '../../core/widgets/app_bottom_sheet.dart';

class SupplierScreen extends StatelessWidget {
  const SupplierScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final supplierProvider = Provider.of<SupplierProvider>(context);
    final profile = Provider.of<ProfileProvider>(context);
    final themeColor = profile.themeColor;

    return Scaffold(
      backgroundColor: profile.scaffoldColor,
      appBar: AppBar(
        title: const Text('SUPPLIERS & VENDORS', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white)),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [themeColor.withValues(alpha: 0.8), themeColor]),
          ),
        ),
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: supplierProvider.suppliers.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.person_outline, size: 80, color: profile.secondaryTextColor.withValues(alpha: 0.2)),
                  const SizedBox(height: 16),
                  Text('No suppliers added yet', style: TextStyle(color: profile.secondaryTextColor, fontWeight: FontWeight.bold)),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: supplierProvider.suppliers.length,
              itemBuilder: (context, index) {
                final supplier = supplierProvider.suppliers[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: profile.cardColor,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade100),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    title: Text(supplier.name, style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor, fontSize: 16)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.inventory_2_outlined, size: 14, color: profile.themeColor),
                              const SizedBox(width: 8),
                              Expanded(child: Text(supplier.itemsSupplied, style: TextStyle(color: profile.secondaryTextColor, fontSize: 12))),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.phone_outlined, size: 14, color: profile.themeColor),
                              const SizedBox(width: 8),
                              Text(supplier.contact, style: TextStyle(color: profile.secondaryTextColor, fontSize: 12)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    trailing: PopupMenuButton(
                      icon: Icon(Icons.more_vert, color: profile.secondaryTextColor),
                      color: profile.cardColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      onSelected: (val) {
                        if (val == 'edit') {
                          _showSupplierBottomSheet(context, supplierProvider, profile, supplier: supplier);
                        } else {
                          _showDeleteConfirm(context, supplierProvider, profile, supplier);
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(value: 'edit', child: Row(children: [const Icon(Icons.edit_outlined, size: 20, color: Colors.blue), const SizedBox(width: 12), Text('Edit', style: TextStyle(color: profile.textColor))])),
                        PopupMenuItem(value: 'delete', child: Row(children: [const Icon(Icons.delete_outline, size: 20, color: Colors.red), const SizedBox(width: 12), Text('Delete', style: TextStyle(color: Colors.red))])),
                      ],
                    ),
                    isThreeLine: true,
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showSupplierBottomSheet(context, supplierProvider, profile),
        backgroundColor: themeColor,
        child: const Icon(Icons.person_add, color: Colors.white),
      ),
    );
  }

  void _showDeleteConfirm(BuildContext context, SupplierProvider provider, ProfileProvider profile, SupplierModel supplier) async {
    final confirm = await AppBottomSheet.showAction(
      context: context,
      profile: profile,
      title: 'Delete Supplier?',
      message: 'Are you sure you want to remove "${supplier.name}"?',
      confirmLabel: 'DELETE',
      isDestructive: true,
      icon: Icons.person_remove_outlined,
    );

    if (confirm == true) {
      provider.softDeleteSupplier(supplier.id!);
    }
  }

  void _showSupplierBottomSheet(BuildContext context, SupplierProvider provider, ProfileProvider profile, {SupplierModel? supplier}) {
    final themeColor = profile.themeColor;
    final nameController = TextEditingController(text: supplier?.name);
    final contactController = TextEditingController(text: supplier?.contact);
    final itemsController = TextEditingController(text: supplier?.itemsSupplied);

    AppBottomSheet.show(
      context: context,
      profile: profile,
      title: supplier == null ? 'ADD NEW SUPPLIER' : 'EDIT SUPPLIER DETAILS',
      footer: ElevatedButton(
        onPressed: () {
          if (nameController.text.isNotEmpty) {
            final newSupplier = SupplierModel(
              id: supplier?.id,
              name: nameController.text,
              contact: contactController.text,
              itemsSupplied: itemsController.text,
            );
            if (supplier == null) {
              provider.addSupplier(newSupplier);
            } else {
              provider.updateSupplier(newSupplier);
            }
            Navigator.pop(context);
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: themeColor,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 60),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          elevation: 0,
        ),
        child: Text(supplier == null ? 'SAVE SUPPLIER' : 'UPDATE DETAILS',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sheetTextField(nameController, 'Supplier / Shop Name', Icons.store_outlined, profile),
          const SizedBox(height: 16),
          _sheetTextField(contactController, 'Contact Number', Icons.phone_outlined, profile, isNumber: true),
          const SizedBox(height: 16),
          _sheetTextField(itemsController, 'Items Supplied', Icons.inventory_2_outlined, profile, maxLines: 2),
        ],
      ),
    );
  }


  Widget _sheetTextField(TextEditingController controller, String label, IconData icon, ProfileProvider profile, {bool isNumber = false, int maxLines = 1}) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? TextInputType.number : TextInputType.text,
      maxLines: maxLines,
      style: TextStyle(color: profile.textColor, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: profile.secondaryTextColor, fontSize: 12),
        prefixIcon: Icon(icon, color: profile.themeColor, size: 20),
        filled: true,
        fillColor: profile.scaffoldColor,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: profile.themeColor, width: 1.5)),
      ),
    );
  }
}
