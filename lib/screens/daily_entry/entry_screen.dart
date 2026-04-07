import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/item_provider.dart';
import '../../models/item_model.dart';
import '../../models/category_model.dart';
import '../../providers/category_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/unit_provider.dart';
import '../../models/transaction_model.dart';
import '../../models/cart_item.dart';
import '../../utils/app_formatter.dart';
import '../../utils/report_helper.dart';
import 'cart_details_screen.dart';

class EntryScreen extends StatefulWidget {
  final TransactionModel? transaction;
  final String? initialType;
  final String? initialCategory;

  const EntryScreen({
    super.key,
    this.transaction,
    this.initialType,
    this.initialCategory,
  });

  @override
  State<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends State<EntryScreen> with TickerProviderStateMixin {
  late String _type;
  late DateTime _selectedDate;
  final List<CartItem> _cart = [];
  String _searchQuery = '';
  TabController? _tabController;
  final TextEditingController _searchController = TextEditingController();

  bool get _isSellingType => _type.toLowerCase() == 'sale' || _type.toLowerCase() == 'income';

  @override
  void initState() {
    super.initState();
    _type = widget.initialType ?? (widget.transaction?.type ?? 'sale');
    if (_type == 'Income') _type = 'sale';
    if (_type == 'Expense') _type = 'purchase';
    
    _selectedDate = widget.transaction?.date ?? DateTime.now();

    if (widget.transaction != null) {
      _loadExistingItems();
    }
  }

  void _loadExistingItems() {
    final itemProvider = Provider.of<ItemProvider>(context, listen: false);
    final items = widget.transaction!.parsedItems;
    for (var itemMap in items) {
      try {
        final name = itemMap['name'];
        final qty = double.tryParse(itemMap['qty'].toString()) ?? 1.0;
        final price = double.tryParse(itemMap['price'].toString()) ?? 0.0;
        final variant = itemMap['variant'] ?? 'Full';
        final unit = itemMap['unit'] ?? 'Full';
        final servingMethod = itemMap['serving_method'] ?? 'Dine-in';
        final table = itemMap['table_number'] ?? '1';
        
        // Fix: Loading extra fields from snapshot
        final exQty = double.tryParse(itemMap['extra_qty'].toString()) ?? 0.0;
        final exPrice = double.tryParse(itemMap['extra_price'].toString()) ?? 0.0;

        final item = itemProvider.items.firstWhere((i) => i.name == name);
        _cart.add(CartItem(
          item: item,
          quantity: qty,
          price: price,
          variant: variant,
          unit: unit,
          extraPieces: exQty,
          extraPrice: exPrice,
          servingMethod: servingMethod,
          tableNumber: table,
        ));
      } catch (e) {
        debugPrint("Error loading item into cart: $e");
      }
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _addItemToCart(ItemModel item, {String variant = '', double price = 0, double? manualQty}) {
    setState(() {
      final p = price > 0 ? price : (variant == 'Half' ? (item.halfPrice ?? 0) : (item.price ?? 0));
      final unit = variant == 'Half' ? (item.halfUnit ?? 'Half') : (item.fullUnit ?? 'Full');
      
      double step = manualQty ?? ((variant == 'Half') ? 0.5 : 1.0);

      final existingIndex = _cart.indexWhere((c) => c.item.id == item.id && c.variant == variant && (c.price == p || _isSellingType));
      
      if (existingIndex != -1) {
        _cart[existingIndex].quantity += step;
      } else {
        final profile = Provider.of<ProfileProvider>(context, listen: false);
        _cart.add(CartItem(
          item: item, 
          quantity: step, 
          price: p, 
          variant: variant, 
          unit: unit,
          servingMethod: _isSellingType ? 'Dine-in' : 'N/A',
          tableNumber: profile.totalTables > 0 ? '1' : ''
        ));
      }
    });
  }

  void _removeItemFromCart(ItemModel item) {
    setState(() {
      final existingIndex = _cart.lastIndexWhere((c) => c.item.id == item.id);
      if (existingIndex != -1) {
        double step = (_cart[existingIndex].variant == 'Half') ? 0.5 : 1.0;
        if (_cart[existingIndex].quantity > step) {
          _cart[existingIndex].quantity -= step;
        } else {
          _cart.removeAt(existingIndex);
        }
      }
    });
  }

  void _updateCartItemQuantity(ItemModel item, double newQty) {
    setState(() {
      final existingIndex = _cart.indexWhere((c) => c.item.id == item.id);
      if (existingIndex != -1) {
        if (newQty > 0) {
          _cart[existingIndex].quantity = newQty;
        } else {
          _cart.removeAt(existingIndex);
        }
      }
    });
  }

  void _showManualQuantityDialog(ItemModel item, double currentQty) {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final controller = TextEditingController(text: currentQty.toString());
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: profile.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Enter Quantity', style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Quantity'),
          style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () {
              final newQty = double.tryParse(controller.text) ?? 0;
              _updateCartItemQuantity(item, newQty);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: profile.themeColor, foregroundColor: Colors.white),
            child: const Text('UPDATE'),
          ),
        ],
      ),
    );
  }

  void _showPurchaseEntrySheet(ItemModel item) {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final qtyController = TextEditingController(text: '1');
    final priceController = TextEditingController(text: (item.price ?? 0).toString());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: profile.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: profile.secondaryTextColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            Text('Manual Entry: ${item.name}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: profile.textColor)),
            const SizedBox(height: 24),
            _buildField(qtyController, 'Quantity', Icons.shopping_basket_outlined, profile, isNumber: true),
            const SizedBox(height: 16),
            _buildField(priceController, 'Unit Price', Icons.payments_outlined, profile, isNumber: true, prefix: profile.currencySymbol),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                final qty = double.tryParse(qtyController.text) ?? 0;
                final price = double.tryParse(priceController.text) ?? 0;
                if (qty > 0) {
                  _addItemToCart(item, price: price, manualQty: qty);
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: profile.themeColor,
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              ),
              child: const Text('ADD TO CART', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showVariantPicker(ItemModel item) {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(color: profile.cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(30))),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(item.name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: profile.textColor)),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (item.halfPrice != null && item.halfPrice! > 0)
                    Expanded(
                      child: _variantBtn('Half (${item.halfUnit ?? 'H'})', item.halfPrice!, () {
                        _addItemToCart(item, variant: 'Half', price: item.halfPrice!);
                        Navigator.pop(context);
                      }, profile),
                    ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _variantBtn('Full (${item.fullUnit ?? 'F'})', item.price ?? 0, () {
                      _addItemToCart(item, variant: 'Full', price: item.price ?? 0);
                      Navigator.pop(context);
                    }, profile),
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _variantBtn(String label, double price, VoidCallback onTap, ProfileProvider profile) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: profile.themeColor.withValues(alpha: 0.1),
        foregroundColor: profile.themeColor,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16), 
          side: BorderSide(color: profile.themeColor.withValues(alpha: 0.2))
        ),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text('${profile.currencySymbol}$price', style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }

  void _showItemOptionsBottomSheet(ItemModel item) {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final themeColor = profile.themeColor;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: profile.cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 40, height: 4, decoration: BoxDecoration(color: profile.secondaryTextColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            Text(item.name.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, color: profile.textColor, fontSize: 16, letterSpacing: 1)),
            Text('Stock: ${item.currentStock.toInt()} ${item.unit}', style: TextStyle(color: themeColor, fontWeight: FontWeight.bold, fontSize: 12)),
            const SizedBox(height: 24),
            _optionTile(Icons.inventory_2_outlined, 'Edit Stock', Colors.blue, () {
              Navigator.pop(context);
              _showEditStockDialog(item);
            }, profile),
            _optionTile(Icons.drive_file_move_outlined, 'Move to Category', Colors.orange, () {
              Navigator.pop(context);
              _showMoveCategorySheet(item);
            }, profile),
            _optionTile(Icons.edit_note_outlined, 'Update Item', Colors.green, () {
              Navigator.pop(context);
              _showEditItemSheet(item);
            }, profile),
            _optionTile(Icons.delete_outline_rounded, 'Delete Item', Colors.red, () {
              Navigator.pop(context);
              _showDeleteConfirm(item);
            }, profile),
          ],
        ),
      ),
    );
  }

  Widget _optionTile(IconData icon, String title, Color color, VoidCallback onTap, ProfileProvider profile) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor, fontSize: 14)),
      trailing: Icon(Icons.arrow_forward_ios_rounded, size: 12, color: profile.secondaryTextColor.withValues(alpha: 0.5)),
    );
  }

  void _showEditStockDialog(ItemModel item) {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final controller = TextEditingController(text: item.currentStock.toInt().toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: profile.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Update Stock', style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'New Stock Quantity'),
          style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () {
              final newStock = double.tryParse(controller.text) ?? item.currentStock;
              Provider.of<ItemProvider>(context, listen: false).updateStock(item.id!, newStock);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: profile.themeColor),
            child: const Text('UPDATE', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showMoveCategorySheet(ItemModel item) {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final catProvider = Provider.of<CategoryProvider>(context, listen: false);
    final filteredCats = catProvider.categories.where((c) => c.type == item.itemType).toList();

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(color: profile.cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(32))),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Move to Category', style: TextStyle(fontWeight: FontWeight.w900, color: profile.textColor, fontSize: 18)),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: filteredCats.length,
                itemBuilder: (context, index) {
                  final cat = filteredCats[index];
                  bool isSelected = item.category == cat.name;
                  return ListTile(
                    onTap: () async {
                      item.category = cat.name;
                      await Provider.of<ItemProvider>(context, listen: false).updateItem(item);
                      if (mounted) Navigator.pop(context);
                    },
                    leading: Icon(Icons.folder_open, color: isSelected ? profile.themeColor : profile.secondaryTextColor),
                    title: Text(cat.name, style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, color: profile.textColor)),
                    trailing: isSelected ? Icon(Icons.check_circle, color: profile.themeColor) : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirm(ItemModel item) {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: profile.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Item?', style: TextStyle(color: profile.textColor)),
        content: Text('Are you sure you want to delete "${item.name}"? This will not affect your past history.', style: TextStyle(color: profile.secondaryTextColor)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          TextButton(
            onPressed: () {
              Provider.of<ItemProvider>(context, listen: false).deleteItem(item.id!);
              Navigator.pop(context);
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showEditItemSheet(ItemModel item) {
    final profileProvider = Provider.of<ProfileProvider>(context, listen: false);
    final unitProvider = Provider.of<UnitProvider>(context, listen: false);
    final themeColor = profileProvider.themeColor;
    final nameController = TextEditingController(text: item.name);
    final priceController = TextEditingController(text: item.price?.toString());
    final halfPriceController = TextEditingController(text: item.halfPrice?.toString());
    
    List<String> availableUnitNames = unitProvider.units.map((u) => u.name).toSet().toList();
    String selectedUnit = item.unit;
    if (!availableUnitNames.contains(selectedUnit)) {
      selectedUnit = availableUnitNames.isNotEmpty ? availableUnitNames.first : 'Plate';
    }
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Container(
          decoration: BoxDecoration(color: profileProvider.cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(32))),
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Update Item', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: profileProvider.textColor)),
                const SizedBox(height: 20),
                _buildField(nameController, 'Item Name', Icons.label_important_outline, profileProvider, isCapitalize: true),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(child: _buildField(priceController, 'Price', Icons.payments_outlined, profileProvider, isNumber: true, prefix: profileProvider.currencySymbol)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(color: profileProvider.scaffoldColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: profileProvider.isDarkMode ? Colors.white10 : Colors.grey.shade200)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedUnit,
                            isExpanded: true,
                            dropdownColor: profileProvider.cardColor,
                            style: TextStyle(color: profileProvider.textColor, fontWeight: FontWeight.bold),
                            items: availableUnitNames.map((u) => DropdownMenuItem(value: u, child: Text(u))).toList(),
                            onChanged: (v) {
                              if (v != null) setDialogState(() => selectedUnit = v);
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (item.halfPrice != null) ...[
                  const SizedBox(height: 16),
                  _buildField(halfPriceController, 'Half Price', Icons.payments_outlined, profileProvider, isNumber: true, prefix: profileProvider.currencySymbol),
                ],
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () async {
                    item.name = nameController.text;
                    item.price = double.tryParse(priceController.text);
                    item.halfPrice = double.tryParse(halfPriceController.text);
                    item.unit = selectedUnit;
                    item.fullUnit = selectedUnit;
                    await Provider.of<ItemProvider>(context, listen: false).updateItem(item);
                    if (mounted) Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: themeColor, minimumSize: const Size(double.infinity, 60), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                  child: const Text('UPDATE ITEM', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController controller, String label, IconData icon, ProfileProvider profile, {bool isNumber = false, String? prefix, bool isCapitalize = false}) {
    return TextField(
      controller: controller,
      keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      inputFormatters: isCapitalize ? [AppFormatter.capitalizeWordsFormatter] : null,
      style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold),
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefix,
        prefixIcon: Icon(icon, size: 20),
      ),
    );
  }

  void _showCategoryReorderSheet() {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final catProvider = Provider.of<CategoryProvider>(context, listen: false);
    
    List<CategoryModel> catsToReorder = catProvider.categories
        .where((c) => _isSellingType ? c.type == 'selling' : c.type == 'purchase')
        .toList();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          height: MediaQuery.of(context).size.height * 0.7,
          decoration: BoxDecoration(color: profile.cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(32))),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Text('REORDER CATEGORIES', style: TextStyle(fontWeight: FontWeight.w900, color: profile.textColor, fontSize: 16, letterSpacing: 1)),
              const SizedBox(height: 20),
              Expanded(
                child: ReorderableListView.builder(
                  itemCount: catsToReorder.length,
                  onReorder: (oldIndex, newIndex) async {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final item = catsToReorder.removeAt(oldIndex);
                    catsToReorder.insert(newIndex, item);
                    setSheetState(() {});
                    int masterOldIndex = catProvider.categories.indexOf(item);
                    int masterNewIndex = catProvider.categories.indexOf(catProvider.categories.where((c) => _isSellingType ? c.type == 'selling' : c.type == 'purchase').toList()[newIndex]);
                    await catProvider.reorderCategories(masterOldIndex, masterNewIndex);
                  },
                  itemBuilder: (context, index) {
                    final cat = catsToReorder[index];
                    return ListTile(
                      key: ValueKey(cat.id),
                      leading: Icon(Icons.menu, color: profile.secondaryTextColor.withValues(alpha: 0.5)),
                      title: Text(cat.name, style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor)),
                      trailing: Icon(Icons.drag_handle, color: profile.themeColor),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(backgroundColor: profile.themeColor, minimumSize: const Size(double.infinity, 54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                child: const Text('DONE', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context);
    final catProvider = Provider.of<CategoryProvider>(context);
    final themeColor = profile.themeColor;

    final filteredCats = catProvider.categories.where((c) => _isSellingType ? c.type == 'selling' : c.type == 'purchase').toList();
    
    if (_tabController == null || _tabController!.length != filteredCats.length + 1) {
      final oldIndex = _tabController?.index ?? 0;
      _tabController?.dispose();
      _tabController = TabController(
        length: filteredCats.length + 1, 
        vsync: this,
        initialIndex: oldIndex.clamp(0, filteredCats.length),
      );
      _tabController!.addListener(() {
        if (mounted && !_tabController!.indexIsChanging) {
          setState(() {});
        }
      });
    }

    double width = MediaQuery.of(context).size.width;
    int crossAxisCount = width > 900 ? 5 : (width > 600 ? 3 : 2);

    return Scaffold(
      backgroundColor: profile.scaffoldColor, 
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.close, color: profile.textColor),
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            Text('CREATE NEW ${_type.toUpperCase()}', style: TextStyle(fontWeight: FontWeight.w900, color: profile.textColor, fontSize: 14)),
            Text(DateFormat('dd MMM yyyy').format(_selectedDate), style: TextStyle(color: profile.secondaryTextColor, fontSize: 10)),
          ],
        ),
        backgroundColor: profile.cardColor,
        elevation: 0,
        centerTitle: true,
        actions: [
          IconButton(
            icon: Icon(Icons.sort_rounded, color: themeColor),
            onPressed: _showCategoryReorderSheet,
          ),
          IconButton(
            icon: Icon(Icons.calendar_month_outlined, color: themeColor, size: 20),
            onPressed: () async {
              final date = await ReportHelper.showAppDatePicker(context, _selectedDate, themeColor);
              if (date != null) setState(() => _selectedDate = date);
            },
          ),
        ],
        bottom: _tabController == null ? null : PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: GestureDetector(
            onLongPress: _showCategoryReorderSheet,
            child: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelPadding: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.only(left: 8), 
              labelColor: themeColor,
              unselectedLabelColor: profile.secondaryTextColor,
              indicatorColor: themeColor,
              indicatorWeight: 3,
              labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11),
              tabs: [
                Tab(text: _isSellingType ? 'ALL SALES' : 'ALL ITEMS'),
                ...filteredCats.map((c) => Tab(text: c.name.toUpperCase())),
              ],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _buildSearchBar(profile, filteredCats),
              Expanded(
                child: _tabController == null 
                  ? const Center(child: CircularProgressIndicator()) 
                  : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildItemGrid('All', profile, themeColor, crossAxisCount),
                      ...filteredCats.map((c) => _buildItemGrid(c.name, profile, themeColor, crossAxisCount)),
                    ],
                  ),
              ),
            ],
          ),
          _buildAnimatedCartButton(profile),
        ],
      ),
    );
  }

  Widget _buildItemGrid(String categoryName, ProfileProvider profile, Color themeColor, int crossAxisCount) {
    final itemProvider = Provider.of<ItemProvider>(context);
    final filteredItems = itemProvider.items.where((i) {
      bool matchType = _isSellingType ? i.itemType == 'selling' : i.itemType == 'purchase';
      bool matchCategory = categoryName == 'All' || i.category == categoryName;
      bool matchSearch = i.name.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchType && matchCategory && matchSearch;
    }).toList();

    if (filteredItems.isEmpty) return Center(child: Text('No items found', style: TextStyle(color: profile.secondaryTextColor)));

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount, 
        crossAxisSpacing: 16, 
        mainAxisSpacing: 16, 
        childAspectRatio: 0.82
      ),
      itemCount: filteredItems.length,
      itemBuilder: (context, index) {
        final item = filteredItems[index];
        final cartItemsOfThisItem = _cart.where((c) => c.item.id == item.id).toList();
        double totalCount = cartItemsOfThisItem.fold(0, (sum, c) => sum + c.quantity);
        return _itemCard(item, totalCount, profile, themeColor);
      },
    );
  }

  Widget _buildSearchBar(ProfileProvider profile, List<dynamic> categories) {
    String currentCatName = (_tabController != null && _tabController!.index > 0) ? categories[_tabController!.index - 1].name : (_isSellingType ? 'All Sales' : 'All Items');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: profile.cardColor,
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v),
        decoration: InputDecoration(hintText: 'Search in $currentCatName...', prefixIcon: const Icon(Icons.search, size: 20), contentPadding: EdgeInsets.zero),
      ),
    );
  }

  Widget _itemCard(ItemModel item, double totalCount, ProfileProvider profile, Color themeColor) {
    bool hasAdded = totalCount > 0;
    return Container(
      decoration: BoxDecoration(
        color: profile.cardColor, 
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: themeColor.withValues(alpha: hasAdded ? 0.12 : 0.04), 
            blurRadius: 20, 
            offset: const Offset(0, 10)
          )
        ],
        border: Border.all(
          color: hasAdded ? themeColor : (profile.isDarkMode ? Colors.white10 : Colors.grey.shade200),
          width: hasAdded ? 2.5 : 1
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Section: Category & More
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 6, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: themeColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10)
                      ),
                      child: Text(
                        item.category.toUpperCase(),
                        style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900, color: themeColor, letterSpacing: 0.8),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.more_vert_rounded, size: 20, color: profile.secondaryTextColor.withValues(alpha: 0.7)),
                    onPressed: () => _showItemOptionsBottomSheet(item),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                  ),
                ],
              ),
            ),
            
            // Middle Section: Icon & Name
            Expanded(
              child: InkWell(
                onTap: () {
                  if (_isSellingType) {
                    item.halfPrice != null && item.halfPrice! > 0 ? _showVariantPicker(item) : _addItemToCart(item);
                  } else {
                    _showPurchaseEntrySheet(item);
                  }
                },
                onLongPress: hasAdded ? () => _showManualQuantityDialog(item, totalCount) : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 32, height: 32,
                            decoration: BoxDecoration(color: themeColor.withValues(alpha: 0.05), shape: BoxShape.circle),
                            child: Icon(_getIconForCategory(item.category), size: 16, color: themeColor),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.name,
                              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: profile.textColor, height: 1.1),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: '${profile.currencySymbol}${item.price ?? 0}',
                              style: TextStyle(color: themeColor, fontWeight: FontWeight.w900, fontSize: 18),
                            ),
                            TextSpan(
                              text: ' / ${item.unit}',
                              style: TextStyle(color: profile.secondaryTextColor, fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            
            // Bottom Section: Actions
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
              child: hasAdded && _isSellingType 
                ? _qtyControls(item, totalCount, profile, themeColor) 
                : _addBtn(item, themeColor),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getIconForCategory(String cat) {
    cat = cat.toLowerCase();
    if (cat.contains('burger')) return Icons.lunch_dining_rounded;
    if (cat.contains('pizza')) return Icons.local_pizza_rounded;
    if (cat.contains('drink') || cat.contains('bev')) return Icons.local_drink_rounded;
    if (cat.contains('fries')) return Icons.fastfood_rounded;
    if (cat.contains('sandwich')) return Icons.breakfast_dining_rounded;
    return Icons.fastfood_outlined;
  }

  Widget _qtyControls(ItemModel item, double count, ProfileProvider profile, Color themeColor) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        color: profile.isDarkMode ? Colors.white10 : const Color(0xFFF1F3F9), 
        borderRadius: BorderRadius.circular(14)
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(Icons.remove_circle_rounded, size: 24, color: themeColor.withValues(alpha: 0.8)), 
            onPressed: () => _removeItemFromCart(item), 
            constraints: const BoxConstraints(), 
            padding: EdgeInsets.zero
          ),
          Text(
            count.toStringAsFixed(1), 
            style: TextStyle(fontWeight: FontWeight.w900, color: profile.textColor, fontSize: 14)
          ),
          IconButton(
            icon: Icon(Icons.add_circle_rounded, size: 24, color: themeColor), 
            onPressed: () => item.halfPrice != null && item.halfPrice! > 0 ? _showVariantPicker(item) : _addItemToCart(item), 
            constraints: const BoxConstraints(), 
            padding: EdgeInsets.zero
          ),
        ],
      ),
    );
  }

  Widget _addBtn(ItemModel item, Color themeColor) {
    Color textColor = themeColor.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          if (_isSellingType) {
            item.halfPrice != null && item.halfPrice! > 0 ? _showVariantPicker(item) : _addItemToCart(item);
          } else {
            _showPurchaseEntrySheet(item);
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: themeColor, 
          foregroundColor: textColor,
          elevation: 0, 
          minimumSize: const Size(double.infinity, 42), 
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))
        ),
        child: Text(
          _isSellingType ? 'ADD' : 'ENTER', 
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, letterSpacing: 1)
        ),
      ),
    );
  }

  Widget _buildAnimatedCartButton(ProfileProvider profile) {
    bool show = _cart.isNotEmpty;
    Color textColor = profile.themeColor.computeLuminance() > 0.5 ? Colors.black : Colors.white;
    
    double total = _cart.fold(0.0, (sum, c) {
      if (_isSellingType) {
        if (c.item.halfPrice != null && c.item.halfPrice! > 0) {
          int fullPlates = c.quantity.floor();
          double halfRem = c.quantity - fullPlates;
          return sum + (fullPlates * (c.item.price ?? 0)) + (halfRem > 0 ? c.item.halfPrice! : 0);
        } else {
          return sum + (c.quantity * (c.item.price ?? 0));
        }
      } else {
        return sum + (c.quantity * c.price);
      }
    });

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300), curve: Curves.easeOutBack, bottom: show ? 24 : -100, left: 16, right: 16,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300), opacity: show ? 1.0 : 0.0,
        child: GestureDetector(
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (context) => CartDetailsScreen(cart: _cart, type: _type, selectedCategory: 'All', selectedDate: _selectedDate, existingTransaction: widget.transaction))),
          child: Container(
            height: 60, padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(color: profile.themeColor, borderRadius: BorderRadius.circular(20), boxShadow: [BoxShadow(color: profile.themeColor.withValues(alpha: 0.4), blurRadius: 20, offset: const Offset(0, 8))]),
            child: Row(
              children: [
                Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${_cart.length} ITEMS', style: TextStyle(color: textColor.withValues(alpha: 0.7), fontSize: 10, fontWeight: FontWeight.bold)), Text('${profile.currencySymbol}${total.toStringAsFixed(0)}', style: TextStyle(color: textColor, fontSize: 18, fontWeight: FontWeight.w900))]),
                const Spacer(),
                Text('REVIEW CART', style: TextStyle(fontWeight: FontWeight.w900, color: textColor, fontSize: 14, letterSpacing: 1)),
                const SizedBox(width: 8),
                Icon(Icons.arrow_forward_ios_rounded, size: 14, color: textColor),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
