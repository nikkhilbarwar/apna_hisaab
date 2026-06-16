import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/staff_auth_provider.dart';
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
import '../../core/widgets/app_bottom_sheet.dart';

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

class _EntryScreenState extends State<EntryScreen>
    with TickerProviderStateMixin {
  late String _type;
  late DateTime _selectedDate;
  final List<CartItem> _cart = [];
  String _searchQuery = '';
  TabController? _tabController;
  final TextEditingController _searchController = TextEditingController();

  final ScrollController _categoryScrollController = ScrollController();

  bool get _isSellingType =>
      _type.toLowerCase() == 'sale' || _type.toLowerCase() == 'income';

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateTabController();
  }

  @override
  void didUpdateWidget(covariant EntryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the transaction type changed from outside, we might need to update _type and the controller
    final newType = widget.initialType ?? (widget.transaction?.type ?? 'sale');
    if (newType != _type) {
      setState(() {
        _type = newType;
        if (_type == 'Income') _type = 'sale';
        if (_type == 'Expense') _type = 'purchase';
      });
      _updateTabController();
    }
  }

  void _updateTabController() {
    final catProvider = Provider.of<CategoryProvider>(context);
    final filteredCats = catProvider.categories
        .where(
          (c) => _isSellingType
              ? (c.type == 'selling' || c.type == 'readymade')
              : (c.type == 'purchase' || c.type == 'readymade'),
        )
        .toList();

    final int newLength = filteredCats.length + 1;

    if (_tabController == null || _tabController!.length != newLength) {
      final oldIndex = _tabController?.index ?? 0;
      _tabController?.dispose();
      _tabController = TabController(
        length: newLength,
        vsync: this,
        initialIndex: oldIndex.clamp(0, newLength > 0 ? newLength - 1 : 0),
      );
      _tabController!.addListener(() {
        if (mounted && !_tabController!.indexIsChanging) {
          _scrollToTab(_tabController!.index);
          setState(() {});
        }
      });
    }
  }

  void _scrollToTab(int index) {
    if (_categoryScrollController.hasClients) {
      _categoryScrollController.animateTo(
        index * 100.0, // Approximate width of a tab
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
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
        final exPrice =
            double.tryParse(itemMap['extra_price'].toString()) ?? 0.0;

        final item = itemProvider.items.firstWhere((i) => i.name == name);
        _cart.add(
          CartItem(
            item: item,
            quantity: qty,
            price: price,
            variant: variant,
            unit: unit,
            extraPieces: exQty,
            extraPrice: exPrice,
            servingMethod: servingMethod,
            tableNumber: table,
          ),
        );
      } catch (e) {
        debugPrint("Error loading item into cart: $e");
      }
    }
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _searchController.dispose();
    _categoryScrollController.dispose();
    super.dispose();
  }

  void _addItemToCart(
    ItemModel item, {
    String variant = '',
    double price = 0,
    double? manualQty,
  }) {
    setState(() {
      final p = price > 0
          ? price
          : (!_isSellingType 
              ? (item.purchasePrice ?? item.price ?? 0)
              : (variant == 'Half' ? (item.halfPrice ?? 0) : (item.price ?? 0)));
      final unit = variant == 'Half'
          ? (item.halfUnit ?? 'Half')
          : (item.fullUnit ?? 'Full');

      double step = manualQty ?? ((variant == 'Half') ? 0.5 : 1.0);

      final existingIndex = _cart.indexWhere(
        (c) =>
            c.item.id == item.id &&
            c.variant == variant &&
            (c.price == p || _isSellingType),
      );

      if (existingIndex != -1) {
        _cart[existingIndex].quantity += step;
      } else {
        final profile = Provider.of<ProfileProvider>(context, listen: false);
        _cart.add(
          CartItem(
            item: item,
            quantity: step,
            price: p,
            variant: variant,
            unit: unit,
            servingMethod: _isSellingType ? 'Dine-in' : 'N/A',
            tableNumber: (_isSellingType && profile.totalTables > 0) ? '1' : '',
          ),
        );
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
    final itemProvider = Provider.of<ItemProvider>(context, listen: false);
    final cat = itemProvider.categories.firstWhere(
      (c) => c.name == item.category,
      orElse: () => CategoryModel(name: 'General'),
    );

    if (cat.useCategoryStock == 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Manual quantity adjustment disabled for shared stock categories.',
          ),
        ),
      );
      return;
    }

    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final controller = TextEditingController(text: currentQty.toString());

    AppBottomSheet.show(
      context: context,
      profile: profile,
      title: 'Enter Quantity',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: true,
            style: TextStyle(
              color: profile.textColor,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              labelText: 'Quantity',
              fillColor: profile.scaffoldColor,
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              final newQty = double.tryParse(controller.text) ?? 0;
              _updateCartItemQuantity(item, newQty);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: profile.themeColor,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'UPDATE QUANTITY',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showPurchaseEntrySheet(ItemModel item) {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final qtyController = TextEditingController(text: '1');
    final priceController = TextEditingController(
      text: (item.purchasePrice != null && item.purchasePrice! > 0) 
            ? item.purchasePrice.toString() 
            : (item.price ?? 0).toString(),
    );

    AppBottomSheet.show(
      context: context,
      profile: profile,
      title: 'Manual Entry: ${item.name}',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildField(
            qtyController,
            'Quantity',
            Icons.shopping_basket_outlined,
            profile,
            isNumber: true,
          ),
          const SizedBox(height: 16),
          _buildField(
            priceController,
            'Unit Price',
            Icons.payments_outlined,
            profile,
            isNumber: true,
            prefix: profile.currencySymbol,
          ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
            ),
            child: const Text(
              'ADD TO CART',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showVariantPicker(ItemModel item) {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    AppBottomSheet.show(
      context: context,
      profile: profile,
      title: item.name,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (item.halfPrice != null && item.halfPrice! > 0)
                Expanded(
                  child: _variantBtn(
                    'Half (${item.halfUnit ?? 'H'})',
                    item.halfPrice!,
                    () {
                      _addItemToCart(
                        item,
                        variant: 'Half',
                        price: item.halfPrice!,
                      );
                      Navigator.pop(context);
                    },
                    profile,
                  ),
                ),
              const SizedBox(width: 16),
              Expanded(
                child: _variantBtn(
                  'Full (${item.fullUnit ?? 'F'})',
                  item.price ?? 0,
                  () {
                    _addItemToCart(
                      item,
                      variant: 'Full',
                      price: item.price ?? 0,
                    );
                    Navigator.pop(context);
                  },
                  profile,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _variantBtn(
    String label,
    double price,
    VoidCallback onTap,
    ProfileProvider profile,
  ) {
    return ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: profile.themeColor.withValues(alpha: 0.1),
        foregroundColor: profile.themeColor,
        elevation: 0,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: profile.themeColor.withValues(alpha: 0.2)),
        ),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(
            '${profile.currencySymbol}$price',
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  void _showItemOptionsBottomSheet(ItemModel item) {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final itemProvider = Provider.of<ItemProvider>(context, listen: false);
    final staffAuth = Provider.of<StaffAuthProvider>(context, listen: false);
    final themeColor = profile.themeColor;

    AppBottomSheet.show(
      context: context,
      profile: profile,
      title: item.name,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Stock: ${item.currentStock.toInt()} ${item.unit}',
            style: TextStyle(
              color: themeColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 24),
          if (itemProvider.categories.any(
            (c) => c.name == item.category && c.useCategoryStock == 0,
          ))
            _optionTile(
              Icons.inventory_2_outlined,
              'Edit Stock',
              Colors.blue,
              () {
                if (!staffAuth.hasPermission('can_stock')) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Permission Denied: Stock Access Required')),
                  );
                  return;
                }
                Navigator.pop(context);
                _showEditStockDialog(item);
              },
              profile,
            ),
          _optionTile(
            Icons.drive_file_move_outlined,
            'Move to Category',
            Colors.orange,
            () {
              if (!staffAuth.hasPermission('can_stock')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Permission Denied: Item Management Required')),
                );
                return;
              }
              Navigator.pop(context);
              _showMoveCategorySheet(item);
            },
            profile,
          ),
          _optionTile(
            Icons.edit_note_outlined,
            'Update Item',
            Colors.green,
            () {
              if (!staffAuth.hasPermission('can_stock')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Permission Denied: Item Management Required')),
                );
                return;
              }
              Navigator.pop(context);
              _showEditItemSheet(item);
            },
            profile,
          ),
          _optionTile(
            Icons.delete_outline_rounded,
            'Delete Item',
            Colors.red,
            () {
              if (!staffAuth.hasPermission('can_stock')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Permission Denied: Item Management Required')),
                );
                return;
              }
              Navigator.pop(context);
              _showDeleteConfirm(item);
            },
            profile,
          ),
        ],
      ),
    );
  }

  Widget _optionTile(
    IconData icon,
    String title,
    Color color,
    VoidCallback onTap,
    ProfileProvider profile,
  ) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: profile.textColor,
          fontSize: 14,
        ),
      ),
      trailing: Icon(
        Icons.arrow_forward_ios_rounded,
        size: 12,
        color: profile.secondaryTextColor.withValues(alpha: 0.5),
      ),
    );
  }

  void _showEditStockDialog(ItemModel item) {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final controller = TextEditingController(
      text: item.currentStock.toInt().toString(),
    );
    AppBottomSheet.show(
      context: context,
      profile: profile,
      title: 'Update Stock',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            autofocus: true,
            style: TextStyle(
              color: profile.textColor,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              labelText: 'New Stock Quantity',
              fillColor: profile.scaffoldColor,
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              final newStock =
                  double.tryParse(controller.text) ?? item.currentStock;
              Provider.of<ItemProvider>(
                context,
                listen: false,
              ).updateStock(item.id!, newStock);
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: profile.themeColor,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 56),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'UPDATE STOCK',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  void _showMoveCategorySheet(ItemModel item) {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final catProvider = Provider.of<CategoryProvider>(context, listen: false);
    final filteredCats = catProvider.categories
        .where((c) => c.type == item.itemType)
        .toList();

    AppBottomSheet.show(
      context: context,
      profile: profile,
      title: 'Move to Category',
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: filteredCats.length,
        itemBuilder: (context, index) {
          final cat = filteredCats[index];
          bool isSelected = item.category == cat.name;
          return ListTile(
            onTap: () async {
              item.category = cat.name;
              await Provider.of<ItemProvider>(
                context,
                listen: false,
              ).updateItem(item);
              if (mounted) Navigator.pop(context);
            },
            leading: Icon(
              Icons.folder_open,
              color: isSelected
                  ? profile.themeColor
                  : profile.secondaryTextColor,
            ),
            title: Text(
              cat.name,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: profile.textColor,
              ),
            ),
            trailing: isSelected
                ? Icon(Icons.check_circle, color: profile.themeColor)
                : null,
          );
        },
      ),
    );
  }

  void _showDeleteConfirm(ItemModel item) async {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final confirm = await AppBottomSheet.showAction(
      context: context,
      profile: profile,
      title: 'Delete Item?',
      message:
          'Are you sure you want to delete "${item.name}"? This will not affect your past history.',
      confirmLabel: 'DELETE',
      isDestructive: true,
      icon: Icons.delete_outline_rounded,
    );

    if (confirm == true) {
      Provider.of<ItemProvider>(
        context,
        listen: false,
      ).softDeleteItem(item.id!);
    }
  }

  void _showEditItemSheet(ItemModel item) {
    final profileProvider = Provider.of<ProfileProvider>(
      context,
      listen: false,
    );
    final unitProvider = Provider.of<UnitProvider>(context, listen: false);
    final themeColor = profileProvider.themeColor;
    final nameController = TextEditingController(text: item.name);
    final priceController = TextEditingController(text: item.price?.toString());
    final halfPriceController = TextEditingController(
      text: item.halfPrice?.toString(),
    );
    final minStockController = TextEditingController(
      text: item.minStock.toString(),
    );

    final categoryProvider = Provider.of<CategoryProvider>(
      context,
      listen: false,
    );
    final category = categoryProvider.getCategoryByName(item.category);
    final bool isSharedStock = category?.useCategoryStock == 1;

    List<String> availableUnitNames = unitProvider.units
        .map((u) => u.name)
        .toSet()
        .toList();
    String selectedUnit = item.unit;
    if (!availableUnitNames.contains(selectedUnit)) {
      selectedUnit = availableUnitNames.isNotEmpty
          ? availableUnitNames.first
          : 'Plate';
    }

    AppBottomSheet.show(
      context: context,
      profile: profileProvider,
      title: 'Update Item',
      child: StatefulBuilder(
        builder: (context, setDialogState) => SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildField(
                nameController,
                'Item Name',
                Icons.label_important_outline,
                profileProvider,
                isCapitalize: true,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildField(
                      priceController,
                      'Price',
                      Icons.payments_outlined,
                      profileProvider,
                      isNumber: true,
                      prefix: profileProvider.currencySymbol,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: profileProvider.scaffoldColor,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: profileProvider.isDarkMode
                              ? Colors.white10
                              : Colors.grey.shade200,
                        ),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: selectedUnit,
                          isExpanded: true,
                          dropdownColor: profileProvider.cardColor,
                          style: TextStyle(
                            color: profileProvider.textColor,
                            fontWeight: FontWeight.bold,
                          ),
                          items: availableUnitNames
                              .map(
                                (u) =>
                                    DropdownMenuItem(value: u, child: Text(u)),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v != null)
                              setDialogState(() => selectedUnit = v);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (item.halfPrice != null) ...[
                const SizedBox(height: 16),
                _buildField(
                  halfPriceController,
                  'Half Price',
                  Icons.payments_outlined,
                  profileProvider,
                  isNumber: true,
                  prefix: profileProvider.currencySymbol,
                ),
              ],
              if (!isSharedStock) ...[
                const SizedBox(height: 16),
                _buildField(
                  minStockController,
                  'Low Stock Alert Qty',
                  Icons.notification_important_outlined,
                  profileProvider,
                  isNumber: true,
                ),
              ],
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () async {
                  item.name = nameController.text;
                  item.price = double.tryParse(priceController.text);
                  item.halfPrice = double.tryParse(halfPriceController.text);
                  item.minStock =
                      double.tryParse(minStockController.text) ?? 10;
                  item.unit = selectedUnit;
                  item.fullUnit = selectedUnit;
                  await Provider.of<ItemProvider>(
                    context,
                    listen: false,
                  ).updateItem(item);
                  if (mounted) Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeColor,
                  minimumSize: const Size(double.infinity, 60),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                ),
                child: const Text(
                  'UPDATE ITEM',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(
    TextEditingController controller,
    String label,
    IconData icon,
    ProfileProvider profile, {
    bool isNumber = false,
    String? prefix,
    bool isCapitalize = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: isNumber
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      inputFormatters: isCapitalize
          ? [AppFormatter.capitalizeWordsFormatter]
          : null,
      style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold),
      decoration: InputDecoration(
        labelText: label,
        prefixText: prefix,
        prefixIcon: Icon(icon, size: 20),
      ),
    );
  }

  void _showCategoryReorderSheet() {
    final staffAuth = Provider.of<StaffAuthProvider>(context, listen: false);
    if (!staffAuth.hasPermission('can_sale') && !staffAuth.hasPermission('can_stock')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permission Denied')),
      );
      return;
    }
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final catProvider = Provider.of<CategoryProvider>(context, listen: false);

    List<CategoryModel> catsToReorder = catProvider.categories
        .where(
          (c) => _isSellingType
              ? (c.type == 'selling' || c.type == 'readymade')
              : (c.type == 'purchase' || c.type == 'readymade'),
        )
        .toList();

    AppBottomSheet.show(
      context: context,
      profile: profile,
      title: 'REORDER CATEGORIES',
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: StatefulBuilder(
          builder: (context, setSheetState) => Column(
            children: [
              Expanded(
                child: ReorderableListView.builder(
                  itemCount: catsToReorder.length,
                  onReorder: (oldIndex, newIndex) async {
                    if (newIndex > oldIndex) newIndex -= 1;
                    final item = catsToReorder.removeAt(oldIndex);
                    catsToReorder.insert(newIndex, item);
                    setSheetState(() {});

                    final allCats = catProvider.categories;
                    int masterOldIndex = allCats.indexOf(item);

                    // Find the actual new index in the master list
                    CategoryModel targetCat = catsToReorder[newIndex];
                    int masterNewIndex = allCats.indexOf(targetCat);

                    await catProvider.reorderCategories(
                      masterOldIndex,
                      masterNewIndex,
                    );
                  },
                  itemBuilder: (context, index) {
                    final cat = catsToReorder[index];
                    return ListTile(
                      key: ValueKey(cat.id),
                      leading: Icon(
                        Icons.menu,
                        color: profile.secondaryTextColor.withValues(
                          alpha: 0.5,
                        ),
                      ),
                      title: Text(
                        cat.name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: profile.textColor,
                        ),
                      ),
                      trailing: Icon(
                        Icons.drag_handle,
                        color: profile.themeColor,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: profile.themeColor,
                  minimumSize: const Size(double.infinity, 54),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: const Text(
                  'DONE',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
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

    final filteredCats = catProvider.categories
        .where(
          (c) => _isSellingType
              ? (c.type == 'selling' || c.type == 'readymade')
              : (c.type == 'purchase' || c.type == 'readymade'),
        )
        .toList();

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
            Text(
              'CREATE NEW ${_type.toUpperCase()}',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: profile.textColor,
                fontSize: 14,
              ),
            ),
            Text(
              DateFormat('dd MMM yyyy').format(_selectedDate),
              style: TextStyle(color: profile.secondaryTextColor, fontSize: 10),
            ),
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
            icon: Icon(
              Icons.calendar_month_outlined,
              color: themeColor,
              size: 20,
            ),
            onPressed: () async {
              final date = await ReportHelper.showAppDatePicker(
                context,
                _selectedDate,
                themeColor,
              );
              if (date != null) setState(() => _selectedDate = date);
            },
          ),
        ],
        bottom: _tabController == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(60),
                child: Container(
                  height: 60,
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ListView.builder(
                    controller: _categoryScrollController,
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: filteredCats.length + 1,
                    itemBuilder: (context, index) {
                      bool isSelected = _tabController!.index == index;
                      String title = index == 0
                          ? (_isSellingType ? 'ALL SALES' : 'ALL ITEMS')
                          : filteredCats[index - 1].name.toUpperCase();

                      return GestureDetector(
                        onTap: () => _tabController!.animateTo(index),
                        onLongPress: _showCategoryReorderSheet,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 6,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? themeColor
                                : themeColor.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(15),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: themeColor.withValues(alpha: 0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : [],
                            border: Border.all(
                              color: isSelected
                                  ? themeColor
                                  : Colors.transparent,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            title,
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : profile.secondaryTextColor,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      );
                    },
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
                          _buildItemGrid(
                            'All',
                            profile,
                            themeColor,
                            crossAxisCount,
                          ),
                          ...filteredCats.map(
                            (c) => _buildItemGrid(
                              c.name,
                              profile,
                              themeColor,
                              crossAxisCount,
                            ),
                          ),
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

  Widget _buildItemGrid(
    String categoryName,
    ProfileProvider profile,
    Color themeColor,
    int crossAxisCount,
  ) {
    final itemProvider = Provider.of<ItemProvider>(context);
    final filteredItems = itemProvider.items.where((i) {
      bool matchType = _isSellingType
          ? (i.itemType == 'selling' || i.itemType == 'readymade')
          : (i.itemType == 'purchase' || i.itemType == 'readymade');
      bool matchCategory =
          categoryName == 'All' ||
          i.category.trim().toLowerCase() == categoryName.trim().toLowerCase();
      bool matchSearch = i.name.toLowerCase().contains(
        _searchQuery.toLowerCase(),
      );
      return matchType && matchCategory && matchSearch;
    }).toList();

    if (filteredItems.isEmpty)
      return Center(
        child: Text(
          'No items found',
          style: TextStyle(color: profile.secondaryTextColor),
        ),
      );

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.95,
      ),
      itemCount: filteredItems.length,
      itemBuilder: (context, index) {
        final item = filteredItems[index];
        final cartItemsOfThisItem = _cart
            .where((c) => c.item.id == item.id)
            .toList();
        double totalCount = cartItemsOfThisItem.fold(
          0,
          (sum, c) => sum + c.quantity,
        );
        return _itemCard(item, totalCount, profile, themeColor);
      },
    );
  }

  Widget _buildSearchBar(ProfileProvider profile, List<dynamic> categories) {
    String currentCatName =
        (_tabController != null && _tabController!.index > 0)
        ? categories[_tabController!.index - 1].name
        : (_isSellingType ? 'All Sales' : 'All Items');
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: profile.cardColor,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v),
        style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          hintText: 'Search in $currentCatName...',
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 22,
            color: profile.themeColor.withValues(alpha: .5),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 0,
          ),
          filled: true,
          fillColor: profile.scaffoldColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none,
          ),
          hintStyle: TextStyle(
            color: profile.secondaryTextColor.withValues(alpha: 0.5),
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _itemCard(
    ItemModel item,
    double totalCount,
    ProfileProvider profile,
    Color themeColor,
  ) {
    bool hasAdded = totalCount > 0;
    return Container(
      decoration: BoxDecoration(
        color: profile.cardColor,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: themeColor.withValues(alpha: hasAdded ? 0.1 : 0.03),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: hasAdded
              ? themeColor
              : (profile.isDarkMode ? Colors.white10 : Colors.grey.shade200),
          width: hasAdded ? 2 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top Section: Category & More
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: themeColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        item.category.toUpperCase(),
                        style: TextStyle(
                          fontSize: 7,
                          fontWeight: FontWeight.w900,
                          color: themeColor,
                          letterSpacing: 0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.more_vert_rounded,
                      size: 18,
                      color: profile.secondaryTextColor.withValues(alpha: 0.5),
                    ),
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
                    item.halfPrice != null && item.halfPrice! > 0
                        ? _showVariantPicker(item)
                        : _addItemToCart(item);
                  } else {
                    _showPurchaseEntrySheet(item);
                  }
                },
                onLongPress: hasAdded
                    ? () => _showManualQuantityDialog(item, totalCount)
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: themeColor.withValues(alpha: .08),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            alignment: Alignment.center,
                            child: item.icon != null && item.icon!.isNotEmpty
                                ? item.icon!.startsWith('base64:')
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          child: Image.memory(
                                            base64Decode(
                                              item.icon!.substring(7),
                                            ),
                                            width: 32,
                                            height: 32,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (
                                                  context,
                                                  error,
                                                  stackTrace,
                                                ) => Icon(
                                                  Icons.broken_image_outlined,
                                                  size: 14,
                                                  color: themeColor,
                                                ),
                                          ),
                                        )
                                      : (item.icon!.startsWith('/') ||
                                            item.icon!.contains('data/user'))
                                      ? ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          child: Image.file(
                                            File(item.icon!),
                                            width: 32,
                                            height: 32,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (
                                                  context,
                                                  error,
                                                  stackTrace,
                                                ) => Icon(
                                                  Icons.broken_image_outlined,
                                                  size: 14,
                                                  color: themeColor,
                                                ),
                                          ),
                                        )
                                      : Text(
                                          item.icon!,
                                          style: const TextStyle(fontSize: 16),
                                        )
                                : Icon(
                                    _getIconForCategory(item.category),
                                    size: 14,
                                    color: themeColor,
                                  ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 13,
                                color: profile.textColor,
                                height: 1.1,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: _isSellingType 
                                ? '${profile.currencySymbol}${item.price ?? 0}'
                                : '${profile.currencySymbol}${item.purchasePrice ?? item.price ?? 0}',
                              style: TextStyle(
                                color: themeColor,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                            TextSpan(
                              text: ' / ${item.unit}',
                              style: TextStyle(
                                color: profile.secondaryTextColor,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
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
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
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
    if (cat.contains('drink') || cat.contains('bev'))
      return Icons.local_drink_rounded;
    if (cat.contains('fries')) return Icons.fastfood_rounded;
    if (cat.contains('sandwich')) return Icons.breakfast_dining_rounded;
    return Icons.fastfood_outlined;
  }

  Widget _qtyControls(
    ItemModel item,
    double count,
    ProfileProvider profile,
    Color themeColor,
  ) {
    final itemProvider = Provider.of<ItemProvider>(context, listen: false);
    final isShared = itemProvider.categories.any(
      (c) => c.name == item.category && c.useCategoryStock == 1,
    );

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: profile.isDarkMode ? Colors.white10 : const Color(0xFFF1F3F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(
            icon: Icon(
              Icons.remove_circle_rounded,
              size: 22,
              color: themeColor.withValues(alpha: .8),
            ),
            onPressed: () => _removeItemFromCart(item),
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
          ),
          Text(
            count % 1 == 0
                ? count.toInt().toString()
                : count.toStringAsFixed(1),
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: profile.textColor,
              fontSize: 13,
            ),
          ),
          IconButton(
            icon: Icon(Icons.add_circle_rounded, size: 22, color: themeColor),
            onPressed: () {
              if (isShared) {
                _addItemToCart(item);
              } else {
                item.halfPrice != null && item.halfPrice! > 0
                    ? _showVariantPicker(item)
                    : _addItemToCart(item);
              }
            },
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  Widget _addBtn(ItemModel item, Color themeColor) {
    Color textColor = themeColor.computeLuminance() > 0.5
        ? Colors.black
        : Colors.white;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          if (_isSellingType) {
            item.halfPrice != null && item.halfPrice! > 0
                ? _showVariantPicker(item)
                : _addItemToCart(item);
          } else {
            _showPurchaseEntrySheet(item);
          }
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: themeColor,
          foregroundColor: textColor,
          elevation: 0,
          minimumSize: const Size(double.infinity, 38),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: Text(
          _isSellingType ? 'ADD' : 'ENTER',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedCartButton(ProfileProvider profile) {
    bool show = _cart.isNotEmpty;
    Color textColor = profile.themeColor.computeLuminance() > 0.5
        ? Colors.black
        : Colors.white;

    double total = _cart.fold(0.0, (sum, c) {
      if (_isSellingType) {
        if (c.item.halfPrice != null && c.item.halfPrice! > 0) {
          int fullPlates = c.quantity.floor();
          double halfRem = c.quantity - fullPlates;
          return sum +
              (fullPlates * (c.item.price ?? 0)) +
              (halfRem > 0 ? c.item.halfPrice! : 0);
        } else {
          return sum + (c.quantity * (c.item.price ?? 0));
        }
      } else {
        return sum + (c.quantity * c.price);
      }
    });

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutBack,
      bottom: show ? 24 : -100,
      left: 16,
      right: 16,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: show ? 1.0 : 0.0,
        child: GestureDetector(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CartDetailsScreen(
                cart: _cart,
                type: _type,
                selectedCategory: 'All',
                selectedDate: _selectedDate,
                existingTransaction: widget.transaction,
              ),
            ),
          ),
          child: Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: profile.themeColor.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: profile.themeColor.withValues(alpha: 0.4),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_cart.length} ITEMS',
                      style: TextStyle(
                        color: textColor.withValues(alpha: 0.7),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      '${profile.currencySymbol}${total.toStringAsFixed(0)}',
                      style: TextStyle(
                        color: textColor,
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Text(
                  'REVIEW CART',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: textColor,
                    fontSize: 14,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 14,
                  color: textColor,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
