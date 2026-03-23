import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/item_provider.dart';
import '../../models/item_model.dart';
import '../../providers/profile_provider.dart';
import '../../providers/category_provider.dart';
import '../../utils/app_formatter.dart';

class ItemManagementScreen extends StatefulWidget {
  final String category;
  final ItemModel? editItem;

  const ItemManagementScreen({super.key, required this.category, this.editItem});

  @override
  State<ItemManagementScreen> createState() => _ItemManagementScreenState();
}

class _ItemManagementScreenState extends State<ItemManagementScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.editItem != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showItemBottomSheet(context, Provider.of<ItemProvider>(context, listen: false), item: widget.editItem);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemProvider = Provider.of<ItemProvider>(context);
    final profileProvider = Provider.of<ProfileProvider>(context);
    final themeColor = profileProvider.themeColor;
    final items = itemProvider.getItemsByCategory(widget.category);

    return Scaffold(
      backgroundColor: profileProvider.scaffoldColor,
      appBar: AppBar(
        title: Text('MANAGE ${widget.category.toUpperCase()}', 
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white)),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [themeColor.withOpacity(0.8), themeColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 64, color: profileProvider.secondaryTextColor.withOpacity(0.2)),
                        const SizedBox(height: 16),
                        Text('No items added yet in ${widget.category}', style: TextStyle(color: profileProvider.secondaryTextColor, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: profileProvider.cardColor,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
                          border: Border.all(color: profileProvider.isDarkMode ? Colors.white10 : Colors.grey.shade100),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: (item.itemType == 'selling' ? Colors.green : Colors.orange).withOpacity(0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              item.itemType == 'selling' ? Icons.sell_outlined : Icons.inventory_2_outlined, 
                              color: item.itemType == 'selling' ? Colors.green : Colors.orange, 
                              size: 20
                            ),
                          ),
                          title: Text(item.name, style: TextStyle(fontWeight: FontWeight.bold, color: profileProvider.textColor)),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (item.itemType == 'selling' ? Colors.green : Colors.orange).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  item.itemType == 'selling' ? 'SALE ITEM' : 'PURCHASE ITEM', 
                                  style: TextStyle(color: item.itemType == 'selling' ? Colors.green : Colors.orange, fontSize: 9, fontWeight: FontWeight.bold)
                                ),
                              ),
                              if (item.itemType == 'selling') ...[
                                const SizedBox(height: 4),
                                Text(item.price != null ? 'Price: ${profileProvider.currencySymbol}${item.price}${item.halfPrice != null ? ' | Half: ${profileProvider.currencySymbol}${item.halfPrice}' : ''}' : 'Price not set',
                                  style: TextStyle(color: profileProvider.secondaryTextColor, fontSize: 12)),
                              ],
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, color: Colors.blue, size: 20),
                                onPressed: () => _showItemBottomSheet(context, itemProvider, item: item),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                                onPressed: () => _showDeleteConfirm(context, itemProvider, profileProvider, item),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: profileProvider.cardColor,
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5)),
              ],
              borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            ),
            child: SafeArea(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 60),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  elevation: 0,
                ),
                onPressed: () {
                  final catProvider = Provider.of<CategoryProvider>(context, listen: false);
                  final category = catProvider.getCategoryByName(widget.category);
                  
                  if (category != null) {
                    _showItemBottomSheet(context, itemProvider, type: category.type);
                  } else {
                    _showTypeSelectionBottomSheet(context, itemProvider, profileProvider);
                  }
                },
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_circle_outline),
                    SizedBox(width: 10),
                    Text('ADD NEW ITEM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 1)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showTypeSelectionBottomSheet(BuildContext context, ItemProvider provider, ProfileProvider profile) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: profile.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(color: profile.secondaryTextColor.withOpacity(0.2), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text('Add New Item', style: TextStyle(fontWeight: FontWeight.w900, color: profile.textColor, fontSize: 20)),
            const SizedBox(height: 8),
            Text('What kind of item is this?', style: TextStyle(color: profile.secondaryTextColor)),
            const SizedBox(height: 24),
            _typeOptionTile(
              context, 
              'Selling Item', 
              'Items you sell to customers', 
              Icons.sell_outlined, 
              Colors.green, 
              () {
                Navigator.pop(context);
                _showItemBottomSheet(context, provider, type: 'selling');
              }
            ),
            const SizedBox(height: 12),
            _typeOptionTile(
              context, 
              'Purchase Item', 
              'Raw materials or expenses', 
              Icons.inventory_2_outlined, 
              Colors.orange, 
              () {
                Navigator.pop(context);
                _showItemBottomSheet(context, provider, type: 'purchase');
              }
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _typeOptionTile(BuildContext context, String title, String sub, IconData icon, Color color, VoidCallback onTap) {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: color.withOpacity(0.2)),
          borderRadius: BorderRadius.circular(16),
          color: color.withOpacity(0.05),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor, fontSize: 14)),
                  Text(sub, style: TextStyle(fontSize: 10, color: profile.secondaryTextColor)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: profile.secondaryTextColor.withOpacity(0.5)),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirm(BuildContext context, ItemProvider provider, ProfileProvider profile, ItemModel item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: profile.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Item?', style: TextStyle(color: profile.textColor)),
        content: Text('Are you sure you want to delete "${item.name}"?', style: TextStyle(color: profile.secondaryTextColor)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          TextButton(
            onPressed: () {
              provider.deleteItem(item.id!);
              Navigator.pop(context);
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showItemBottomSheet(BuildContext context, ItemProvider provider, {ItemModel? item, String? type}) {
    final profileProvider = Provider.of<ProfileProvider>(context, listen: false);
    final themeColor = profileProvider.themeColor;
    final nameController = TextEditingController(text: item?.name);
    final priceController = TextEditingController(text: item?.price?.toString());
    final halfPriceController = TextEditingController(text: item?.halfPrice?.toString());
    
    String selectedUnit = item?.fullUnit ?? 'Plate';
    final List<String> unitOptions = ['Plate', "Pc's", 'Packet'];
    
    final halfUnitController = TextEditingController(text: item?.halfUnit ?? 'Half Plate');
    final fullQtyController = TextEditingController(text: item?.fullQty?.toString() ?? '1');
    final halfQtyController = TextEditingController(text: item?.halfQty?.toString() ?? '0.5');
    
    bool hasHalfOption = item?.halfPrice != null;
    String selectedItemType = type ?? item?.itemType ?? 'selling';
    final isEditing = item != null;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Container(
          decoration: BoxDecoration(
            color: profileProvider.cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 24),
                    decoration: BoxDecoration(color: profileProvider.secondaryTextColor.withOpacity(0.2), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(isEditing ? 'Edit Item' : 'New Item Details', 
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: profileProvider.textColor)),
                    IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.close_rounded, color: profileProvider.textColor)),
                  ],
                ),
                const SizedBox(height: 20),
                
                // Type Indicator
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: selectedItemType == 'selling' ? Colors.green.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: (selectedItemType == 'selling' ? Colors.green : Colors.orange).withOpacity(0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(selectedItemType == 'selling' ? Icons.sell_outlined : Icons.inventory_2_outlined, 
                        size: 14, color: selectedItemType == 'selling' ? Colors.green : Colors.orange),
                      const SizedBox(width: 8),
                      Text(
                        selectedItemType == 'selling' ? 'SELLING ITEM (SALES)' : 'PURCHASE ITEM (RAW MATERIAL)',
                        style: TextStyle(color: selectedItemType == 'selling' ? Colors.green : Colors.orange, fontWeight: FontWeight.w900, fontSize: 10, letterSpacing: 0.5),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                
                _buildField(nameController, 'Item Name', Icons.label_important_outline, profileProvider, 
                  hint: selectedItemType == 'selling' ? 'e.g. Cheese Ball' : 'e.g. Potato', isCapitalize: true),
                
                if (selectedItemType == 'selling') ...[
                  const SizedBox(height: 20),
                  Text('PRICING & UNIT', 
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: profileProvider.secondaryTextColor, letterSpacing: 1)),
                  const SizedBox(height: 12),
                  
                  Row(
                    children: [
                      Expanded(
                        child: _buildField(priceController, 'Sale Price', Icons.payments_outlined, profileProvider, 
                          isNumber: true, prefix: profileProvider.currencySymbol),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: profileProvider.scaffoldColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: profileProvider.isDarkMode ? Colors.white10 : Colors.grey.shade200),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: unitOptions.contains(selectedUnit) ? selectedUnit : 'Plate',
                              isExpanded: true,
                              dropdownColor: profileProvider.cardColor,
                              style: TextStyle(color: profileProvider.textColor, fontWeight: FontWeight.bold, fontSize: 14),
                              items: unitOptions.map((String value) {
                                return DropdownMenuItem<String>(
                                  value: value,
                                  child: Text(value),
                                );
                              }).toList(),
                              onChanged: (newValue) {
                                if (newValue != null) setDialogState(() => selectedUnit = newValue);
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  
                  const SizedBox(height: 16),
                  _buildField(fullQtyController, 'Deduct Qty per Sale', Icons.inventory_outlined, profileProvider, 
                    isNumber: true, hint: 'e.g. 1'),

                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: Text('Has Half Option?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: profileProvider.textColor)),
                    subtitle: Text('Add pricing for half portions', style: TextStyle(fontSize: 11, color: profileProvider.secondaryTextColor)),
                    value: hasHalfOption,
                    onChanged: (val) => setDialogState(() => hasHalfOption = val),
                    contentPadding: EdgeInsets.zero,
                    activeColor: themeColor,
                  ),
                  
                  if (hasHalfOption) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: profileProvider.scaffoldColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: profileProvider.isDarkMode ? Colors.white10 : Colors.grey.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('HALF PORTION DETAILS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10, color: themeColor, letterSpacing: 1)),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: _buildField(halfPriceController, 'Half Price', Icons.payments_outlined, profileProvider, isNumber: true, prefix: profileProvider.currencySymbol),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: _buildField(halfUnitController, 'Half Unit', Icons.straighten_outlined, profileProvider, hint: 'e.g. Half Plate', isCapitalize: true),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildField(halfQtyController, 'Deduct Qty per Half', Icons.inventory_outlined, profileProvider, isNumber: true),
                        ],
                      ),
                    ),
                  ],
                ],
                
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () async {
                    if (nameController.text.isNotEmpty) {
                      final newItem = ItemModel(
                        id: item?.id,
                        name: nameController.text,
                        category: widget.category,
                        unit: selectedItemType == 'selling' ? selectedUnit : 'pcs',
                        minStock: item?.minStock ?? 0,
                        currentStock: item?.currentStock ?? 0,
                        price: selectedItemType == 'selling' ? double.tryParse(priceController.text) : null,
                        halfPrice: (selectedItemType == 'selling' && hasHalfOption) ? double.tryParse(halfPriceController.text) : null,
                        fullUnit: selectedItemType == 'selling' ? selectedUnit : 'pcs',
                        halfUnit: (selectedItemType == 'selling' && hasHalfOption) ? halfUnitController.text : null,
                        fullQty: selectedItemType == 'selling' ? double.tryParse(fullQtyController.text) : 1,
                        halfQty: (selectedItemType == 'selling' && hasHalfOption) ? double.tryParse(halfQtyController.text) : 0.5,
                        itemType: selectedItemType,
                      );
                      
                      bool success;
                      if (isEditing) {
                        success = await provider.updateItem(newItem);
                      } else {
                        success = await provider.addItem(newItem);
                      }
                      
                      if (success) {
                        Navigator.pop(context);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Item with this name already exists in inventory!'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeColor,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 60),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                    elevation: 0,
                  ),
                  child: Text(isEditing ? 'UPDATE ITEM' : 'SAVE ITEM', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String label, IconData icon, ProfileProvider profile, {bool isNumber = false, String? prefix, String? hint, bool isCapitalize = false}) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      inputFormatters: isCapitalize ? [AppFormatter.capitalizeWordsFormatter] : null,
      onTap: () {
        if (isNumber && (controller.text == '0' || controller.text == '0.0')) {
          controller.clear();
        }
      },
      style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixText: prefix,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: profile.scaffoldColor,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade200)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: profile.themeColor, width: 2)),
      ),
    );
  }
}
