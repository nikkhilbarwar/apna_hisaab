import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../models/category_model.dart';
import '../../utils/image_helper.dart';
import '../../providers/item_provider.dart';
import '../../models/item_model.dart';
import '../../models/recipe_model.dart';
import '../../providers/profile_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/unit_provider.dart';
import '../../utils/app_formatter.dart';

class ItemManagementScreen extends StatefulWidget {
  final String category;
  final ItemModel? editItem;

  const ItemManagementScreen({
    super.key,
    required this.category,
    this.editItem,
  });

  @override
  State<ItemManagementScreen> createState() => _ItemManagementScreenState();
}

class _ItemManagementScreenState extends State<ItemManagementScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  bool _isSearching = false;
  List<int> _tempLinkedItemIds = [];
  List<int> _tempLinkedCategoryIds = [];

  @override
  void initState() {
    super.initState();
    if (widget.editItem != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showItemBottomSheet(
          context,
          Provider.of<ItemProvider>(context, listen: false),
          item: widget.editItem,
        );
      });
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final itemProvider = Provider.of<ItemProvider>(context);
    final profileProvider = Provider.of<ProfileProvider>(context);
    final themeColor = profileProvider.themeColor;

    final allItems = itemProvider.getItemsByCategory(widget.category);
    final filteredItems = allItems
        .where(
          (item) =>
              item.name.toLowerCase().contains(_searchQuery.toLowerCase()),
        )
        .toList();

    return Scaffold(
      backgroundColor: profileProvider.scaffoldColor,
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                decoration: const InputDecoration(
                  hintText: "Search items...",
                  hintStyle: TextStyle(color: Colors.white70),
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  enabledBorder: InputBorder.none,
                ),
                onChanged: (value) {
                  setState(() => _searchQuery = value);
                },
              )
            : Text(
                'MANAGE ${widget.category.toUpperCase()}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  color: Colors.white,
                ),
              ),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [themeColor.withValues(alpha: 0.8), themeColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchQuery = "";
                  _searchController.clear();
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: filteredItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _searchQuery.isEmpty
                              ? Icons.inventory_2_outlined
                              : Icons.search_off_rounded,
                          size: 64,
                          color: profileProvider.secondaryTextColor.withValues(
                            alpha: 0.2,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isEmpty
                              ? 'No items added yet in ${widget.category}'
                              : 'No results found for "$_searchQuery"',
                          style: TextStyle(
                            color: profileProvider.secondaryTextColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: filteredItems.length,
                    itemBuilder: (context, index) {
                      final item = filteredItems[index];
                      return Hero(
                        tag: 'item_card_${item.id}',
                        child: Material(
                          color: Colors.transparent,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: profileProvider.cardColor,
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                              border: Border.all(
                                color: profileProvider.isDarkMode
                                    ? Colors.white10
                                    : Colors.grey.shade100,
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              leading: Container(
                                height: 50,
                                width: 50,
                                decoration: BoxDecoration(
                                  color:
                                      (item.itemType == 'selling'
                                              ? Colors.green
                                              : Colors.orange)
                                          .withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(15),
                                ),
                                alignment: Alignment.center,
                                child: item.icon != null && item.icon!.isNotEmpty
                                    ? item.icon!.startsWith('base64:')
                                          ? ClipRRect(
                                              borderRadius: BorderRadius.circular(
                                                15,
                                              ),
                                              child: Image.memory(
                                                base64Decode(
                                                  item.icon!.substring(7),
                                                ),
                                                width: 50,
                                                height: 50,
                                                fit: BoxFit.cover,
                                                errorBuilder:
                                                    (
                                                      context,
                                                      error,
                                                      stackTrace,
                                                    ) => const Icon(
                                                      Icons.broken_image_outlined,
                                                      size: 20,
                                                    ),
                                              ),
                                            )
                                          : (item.icon!.startsWith('/') ||
                                                item.icon!.contains(
                                                  'data/user',
                                                ))
                                          ? ClipRRect(
                                              borderRadius: BorderRadius.circular(
                                                15,
                                              ),
                                              child: Image.file(
                                                File(item.icon!),
                                                width: 50,
                                                height: 50,
                                                fit: BoxFit.cover,
                                                errorBuilder:
                                                    (
                                                      context,
                                                      error,
                                                      stackTrace,
                                                    ) => const Icon(
                                                      Icons.broken_image_outlined,
                                                      size: 20,
                                                    ),
                                              ),
                                            )
                                          : Text(
                                              item.icon!,
                                              style: const TextStyle(fontSize: 24),
                                            )
                                    : Icon(
                                        item.itemType == 'selling'
                                            ? Icons.sell_outlined
                                            : Icons.inventory_2_outlined,
                                        color: item.itemType == 'selling'
                                            ? Colors.green
                                            : Colors.orange,
                                        size: 24,
                                      ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.name,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        color: profileProvider.textColor,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                  Builder(
                                    builder: (context) {
                                      double displayStock = item.currentStock;
                                      String unitLabel = item.unit;
                                      
                                      // Logic: If purchase item with multiplier, show converted units
                                      if (item.itemType == 'purchase' && item.fullQty != null && item.fullQty! > 1) {
                                        displayStock = item.currentStock / item.fullQty!;
                                      }

                                      return Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: profileProvider.scaffoldColor,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(color: profileProvider.isDarkMode ? Colors.white10 : Colors.grey.shade200),
                                        ),
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              '${displayStock % 1 == 0 ? displayStock.toInt() : displayStock.toStringAsFixed(1)}',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: (item.currentStock <= item.minStock) ? Colors.red : profileProvider.themeColor,
                                                fontSize: 14,
                                              ),
                                            ),
                                            Text(
                                              unitLabel,
                                              style: TextStyle(fontSize: 9, color: profileProvider.secondaryTextColor),
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ],
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const SizedBox(height: 6),
                                  Row(
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 3,
                                        ),
                                        decoration: BoxDecoration(
                                          color:
                                              (item.itemType == 'selling'
                                                      ? Colors.green
                                                      : (item.itemType ==
                                                                'readymade'
                                                            ? Colors.blue
                                                            : Colors.orange))
                                                  .withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(
                                            color:
                                                (item.itemType == 'selling'
                                                        ? Colors.green
                                                        : (item.itemType ==
                                                                  'readymade'
                                                              ? Colors.blue
                                                              : Colors.orange))
                                                    .withValues(alpha: 0.2),
                                          ),
                                        ),
                                        child: Text(
                                          item.itemType == 'selling'
                                              ? 'SALE ITEM'
                                              : (item.itemType == 'readymade'
                                                    ? 'READYMADE'
                                                    : 'PURCHASE ITEM'),
                                          style: TextStyle(
                                            color: item.itemType == 'selling'
                                                ? Colors.green
                                                : (item.itemType == 'readymade'
                                                      ? Colors.blue
                                                      : Colors.orange),
                                            fontSize: 8,
                                            fontWeight: FontWeight.w900,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        item.unit,
                                        style: TextStyle(
                                          color: profileProvider.secondaryTextColor
                                              .withValues(alpha: 0.6),
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (item.itemType == 'selling' ||
                                      item.itemType == 'readymade') ...[
                                    const SizedBox(height: 6),
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.payments_outlined,
                                          size: 14,
                                          color: profileProvider.secondaryTextColor
                                              .withValues(alpha: 0.5),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          item.price != null
                                              ? '${profileProvider.currencySymbol}${item.price}'
                                              : 'Price not set',
                                          style: TextStyle(
                                            color: profileProvider.textColor,
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        if (item.halfPrice != null) ...[
                                          Text(
                                            ' | Half: ',
                                            style: TextStyle(
                                              color: profileProvider
                                                  .secondaryTextColor,
                                              fontSize: 11,
                                            ),
                                          ),
                                          Text(
                                            '${profileProvider.currencySymbol}${item.halfPrice}',
                                            style: TextStyle(
                                              color: themeColor,
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ],
                              ),
                              trailing: Container(
                                decoration: BoxDecoration(
                                  color: profileProvider.scaffoldColor,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(
                                        Icons.edit_rounded,
                                        color: Colors.blue,
                                        size: 18,
                                      ),
                                      onPressed: () => _showItemBottomSheet(
                                        context,
                                        itemProvider,
                                        item: item,
                                      ),
                                      constraints: const BoxConstraints(
                                        minWidth: 40,
                                      ),
                                    ),
                                    Container(
                                      width: 1,
                                      height: 20,
                                      color: Colors.grey.withValues(alpha: 0.1),
                                    ),
                                    IconButton(
                                      icon: const Icon(
                                        Icons.delete_rounded,
                                        color: Colors.red,
                                        size: 18,
                                      ),
                                      onPressed: () => _showDeleteConfirm(
                                        context,
                                        itemProvider,
                                        profileProvider,
                                        item,
                                      ),
                                      constraints: const BoxConstraints(
                                        minWidth: 40,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.all(20),
            child: SafeArea(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeColor,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 60),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  elevation: 0,
                ),
                onPressed: () {
                  final catProvider = Provider.of<CategoryProvider>(
                    context,
                    listen: false,
                  );
                  final category = catProvider.getCategoryByName(
                    widget.category,
                  );
                  final type = category?.type.isNotEmpty == true
                      ? category!.type
                      : 'selling';
                  _showItemBottomSheet(context, itemProvider, type: type);
                },
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_circle_outline),
                    SizedBox(width: 10),
                    Text(
                      'ADD NEW ITEM',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirm(
    BuildContext context,
    ItemProvider provider,
    ProfileProvider profile,
    ItemModel item,
  ) {
    AppBottomSheet.showAction(
      context: context,
      profile: profile,
      title: 'Delete Item?',
      message:
          'Are you sure you want to delete "${item.name}"? This item will be moved to the trash bin.',
      confirmLabel: 'DELETE',
      isDestructive: true,
      icon: Icons.delete_sweep_outlined,
    ).then((confirmed) {
      if (confirmed == true) {
        provider.softDeleteItem(item.id!);
      }
    });
  }

  void _showItemBottomSheet(
    BuildContext context,
    ItemProvider provider, {
    ItemModel? item,
    String? type,
  }) {
    final profileProvider = Provider.of<ProfileProvider>(
      context,
      listen: false,
    );
    final unitProvider = Provider.of<UnitProvider>(context, listen: false);
    final themeColor = profileProvider.themeColor;

    final nameController = TextEditingController(text: item?.name);
    final priceController = TextEditingController(
      text: item?.price?.toString(),
    );
    final purchasePriceController = TextEditingController(
      text: item?.purchasePrice?.toString(),
    );
    final transportCostController = TextEditingController(
      text: item?.transportCost?.toString(),
    );
    final halfPriceController = TextEditingController(
      text: item?.halfPrice?.toString(),
    );
    // New controller for conversion factor (Pieces per Unit)
    final fullQtyController = TextEditingController(
      text: item?.fullQty?.toString(),
    );

    List<String> availableUnitNames = unitProvider.units
        .map((u) => u.name)
        .toSet()
        .toList();
    String selectedUnit =
        item?.unit ??
        (availableUnitNames.isNotEmpty ? availableUnitNames.first : 'Plate');

    if (!availableUnitNames.contains(selectedUnit)) {
      selectedUnit = availableUnitNames.isNotEmpty
          ? availableUnitNames.first
          : 'Plate';
    }

    final minStockController = TextEditingController(
      text: (item?.minStock)?.toString() ?? '10',
    );
    final categoryProvider = Provider.of<CategoryProvider>(
      context,
      listen: false,
    );
    final category = categoryProvider.getCategoryByName(widget.category);
    final bool showTypeSelection =
        type == null && (category == null || category.type.trim().isEmpty);
    
    String selectedItemType = type ?? category?.type ?? item?.itemType ?? 'selling';
    String selectedIcon = item?.icon ?? '🍽️'; 
    bool hasHalfOption = item?.halfPrice != null;
    final isEditing = item != null;

    AppBottomSheet.show(
      context: context,
      profile: profileProvider,
      title: isEditing ? 'Edit Item' : 'New Item Details',
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      footer: StatefulBuilder(
        builder: (context, setDialogState) => SafeArea(
          child: ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Please enter item name')),
                );
                return;
              }
              String finalCategory = widget.category;
              if (selectedItemType == 'purchase') {
                final currentCat = categoryProvider.getCategoryByName(
                  widget.category,
                );
                if (currentCat?.type != 'purchase') {
                  finalCategory = 'Raw Material';
                }
              }

              final newItem = ItemModel(
                id: item?.id,
                name: nameController.text.trim(),
                category: finalCategory,
                unit: selectedUnit,
                minStock: double.tryParse(minStockController.text) ?? 10,
                currentStock:
                    item?.currentStock ??
                    (isEditing
                        ? 0
                        : (category?.useCategoryStock == 1
                            ? category?.stockQty ?? 0
                            : 0)),
                price: double.tryParse(priceController.text),
                purchasePrice: double.tryParse(
                  purchasePriceController.text,
                ),
                transportCost: double.tryParse(transportCostController.text),
                halfPrice:
                    hasHalfOption
                        ? double.tryParse(halfPriceController.text)
                        : null,
                fullQty: double.tryParse(fullQtyController.text),
                itemType: selectedItemType,
                linkedItemIds:
                    isEditing ? item.linkedItemIds : _tempLinkedItemIds,
                linkedCategoryIds:
                    isEditing
                        ? item.linkedCategoryIds
                        : _tempLinkedCategoryIds,
                icon: selectedIcon,
                isSynced: 0,
              );

              bool success =
                  isEditing
                      ? await provider.updateItem(newItem)
                      : await provider.addItem(newItem);
              if (success) {
                if (context.mounted) Navigator.pop(context);
              } else {
                if (context.mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Item name already exists!'),
                    ),
                  );
              }
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              backgroundColor: themeColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              isEditing ? 'UPDATE ITEM' : 'SAVE ITEM',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ),
      child: StatefulBuilder(
        builder: (context, setDialogState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showTypeSelection) ...[
              Text(
                'ITEM TYPE',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  color: profileProvider.secondaryTextColor,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _typeChoice(
                    context,
                    'selling',
                    'SALE',
                    Colors.green,
                    selectedItemType,
                    (v) => setDialogState(() => selectedItemType = v),
                    profileProvider,
                  ),
                  const SizedBox(width: 8),
                  _typeChoice(
                    context,
                    'purchase',
                    'PURCHASE',
                    Colors.orange,
                    selectedItemType,
                    (v) => setDialogState(() => selectedItemType = v),
                    profileProvider,
                  ),
                  const SizedBox(width: 8),
                  _typeChoice(
                    context,
                    'readymade',
                    'READY',
                    Colors.blue,
                    selectedItemType,
                    (v) => setDialogState(() => selectedItemType = v),
                    profileProvider,
                  ),
                ],
              ),
              const SizedBox(height: 20),
            ] else ...[
              Text(
                'ITEM TYPE',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  color: profileProvider.secondaryTextColor,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                decoration: BoxDecoration(
                  color: (selectedItemType == 'selling'
                          ? Colors.green
                          : (selectedItemType == 'purchase'
                              ? Colors.orange
                              : Colors.blue))
                      .withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: (selectedItemType == 'selling'
                            ? Colors.green
                            : (selectedItemType == 'purchase'
                                ? Colors.orange
                                : Colors.blue))
                        .withValues(alpha: 0.2),
                  ),
                ),
                child: Text(
                  selectedItemType.toUpperCase(),
                  style: TextStyle(
                    color: selectedItemType == 'selling'
                        ? Colors.green
                        : (selectedItemType == 'purchase'
                            ? Colors.orange
                            : Colors.blue),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            Center(
              child: Column(
                children: [
                  GestureDetector(
                    onTap:
                        () => _showIconPickerSheet(
                          context,
                          (icon) => setDialogState(() => selectedIcon = icon),
                          selectedIcon,
                        ),
                    child: Container(
                      height: 60,
                      width: 60,
                      decoration: BoxDecoration(
                        color: themeColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: themeColor.withValues(alpha: 0.2),
                          width: 2,
                        ),
                      ),
                      alignment: Alignment.center,
                      child:
                          selectedIcon.startsWith('base64:')
                              ? ClipRRect(
                                borderRadius: BorderRadius.circular(30),
                                child: Image.memory(
                                  base64Decode(
                                    selectedIcon.substring(7),
                                  ),
                                  width: 60,
                                  height: 60,
                                  fit: BoxFit.cover,
                                ),
                              )
                              : (selectedIcon.startsWith('/') ||
                                      selectedIcon.contains(
                                        'data/user',
                                      ))
                              ? ClipRRect(
                                borderRadius: BorderRadius.circular(30),
                                child: Image.file(
                                  File(selectedIcon),
                                  width: 60,
                                  height: 60,
                                  fit: BoxFit.cover,
                                ),
                              )
                              : Text(
                                selectedIcon,
                                style: const TextStyle(fontSize: 30),
                              ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Tap to change icon',
                    style: TextStyle(
                      fontSize: 9,
                      color: profileProvider.secondaryTextColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            _buildField(
              nameController,
              'Item Name',
              Icons.drive_file_rename_outline,
              profileProvider,
              isCapitalize: true,
            ),
            const SizedBox(height: 20),

            if (selectedItemType == 'purchase') ...[
              Text(
                'LINKS TO SELLING TARGETS',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  color: profileProvider.secondaryTextColor,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),

              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ...(isEditing ? item.linkedItemIds : _tempLinkedItemIds).map((
                    id,
                  ) {
                    final linkedItem = provider.allItems.firstWhere(
                      (i) => i.id == id,
                      orElse:
                          () => ItemModel(
                            name: '?',
                            category: '',
                            unit: '',
                            minStock: 0,
                            currentStock: 0,
                          ),
                    );
                    return Chip(
                      label: Text(
                        linkedItem.name,
                        style: const TextStyle(fontSize: 12),
                      ),
                      onDeleted: () {
                        setDialogState(() {
                          if (isEditing) {
                            item.linkedItemIds = List.from(item.linkedItemIds)
                              ..remove(id);
                          } else {
                            _tempLinkedItemIds.remove(id);
                          }
                        });
                      },
                    );
                  }),
                  ...(isEditing
                          ? item.linkedCategoryIds
                          : _tempLinkedCategoryIds)
                      .map((id) {
                        final linkedCat = provider.categories.firstWhere(
                          (c) => c.id == id,
                          orElse:
                              () => CategoryModel(
                                name: '?',
                                iconName: '',
                              ),
                        );
                        return Chip(
                          label: Text(
                            "Cat: ${linkedCat.name}",
                            style: const TextStyle(fontSize: 12),
                          ),
                          onDeleted: () {
                            setDialogState(() {
                              if (isEditing) {
                                item.linkedCategoryIds = List.from(
                                  item.linkedCategoryIds,
                                )..remove(id);
                              } else {
                                _tempLinkedCategoryIds.remove(id);
                              }
                            });
                          },
                        );
                      }),
                  ActionChip(
                    label: const Text("Add Link"),
                    avatar: const Icon(Icons.add, size: 16),
                    onPressed:
                        () => _showMultiSelectBottomSheet(
                          context,
                          provider,
                          profileProvider,
                          isEditing ? item.linkedItemIds : _tempLinkedItemIds,
                          isEditing
                              ? item.linkedCategoryIds
                              : _tempLinkedCategoryIds,
                          (selectedItems, selectedCats) {
                            setDialogState(() {
                              if (isEditing) {
                                item.linkedItemIds = selectedItems;
                                item.linkedCategoryIds = selectedCats;
                              } else {
                                _tempLinkedItemIds = selectedItems;
                                _tempLinkedCategoryIds = selectedCats;
                              }
                            });
                          },
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'UNIT',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          color: profileProvider.secondaryTextColor,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: profileProvider.scaffoldColor,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value:
                                availableUnitNames.contains(selectedUnit)
                                    ? selectedUnit
                                    : null,
                            isExpanded: true,
                            hint: Text(
                              "Select Unit",
                              style: TextStyle(
                                color: profileProvider.secondaryTextColor,
                              ),
                            ),
                            dropdownColor: profileProvider.cardColor,
                            borderRadius: BorderRadius.circular(16),
                            items:
                                availableUnitNames
                                    .map(
                                      (u) => DropdownMenuItem(
                                        value: u,
                                        child: Text(
                                          u,
                                          style: TextStyle(
                                            color: profileProvider.textColor,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                            onChanged: (v) {
                              if (v != null)
                                setDialogState(() => selectedUnit = v);
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 20),
                  child: IconButton.filledTonal(
                    onPressed: () async {
                      final newUnit = await _showAddUnitDialog(
                        context,
                        unitProvider,
                        profileProvider,
                      );
                      if (newUnit != null) {
                        setDialogState(() {
                          availableUnitNames.add(newUnit);
                          selectedUnit = newUnit;
                        });
                      }
                    },
                    icon: const Icon(Icons.add),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (selectedItemType == 'selling' ||
                selectedItemType == 'readymade') ...[
              _buildField(
                priceController,
                'Selling Price',
                Icons.sell_outlined,
                profileProvider,
                isNumber: true,
                prefix: profileProvider.currencySymbol,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(
                    value: hasHalfOption,
                    onChanged:
                        (v) => setDialogState(() => hasHalfOption = v ?? false),
                    activeColor: themeColor,
                  ),
                  Text(
                    'Has Half Portion?',
                    style: TextStyle(
                      color: profileProvider.textColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              if (hasHalfOption) ...[
                const SizedBox(height: 8),
                _buildField(
                  halfPriceController,
                  'Half Price',
                  Icons.adjust_outlined,
                  profileProvider,
                  isNumber: true,
                  prefix: profileProvider.currencySymbol,
                ),
              ],
              const SizedBox(height: 16),
              if (selectedItemType == 'selling') ...[
                _buildRecipeSection(
                  context,
                  provider,
                  item,
                  profileProvider,
                  setDialogState,
                ),
                const SizedBox(height: 16),
              ],
            ],

            if (selectedItemType == 'purchase' ||
                selectedItemType == 'readymade') ...[
              _buildField(
                purchasePriceController,
                'Purchase Price',
                Icons.shopping_cart_outlined,
                profileProvider,
                isNumber: true,
                prefix: profileProvider.currencySymbol,
              ),
              const SizedBox(height: 16),
              _buildField(
                fullQtyController,
                'Pieces per $selectedUnit',
                Icons.layers_outlined,
                profileProvider,
                isNumber: true,
              ),
              Padding(
                padding: const EdgeInsets.only(left: 12, top: 4),
                child: Text(
                  'Example: If 1 packet has 4 buns, enter 4 here.',
                  style: TextStyle(
                    fontSize: 10,
                    color: profileProvider.secondaryTextColor,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            _buildField(
              minStockController,
              'Minimum Stock Alert',
              Icons.warning_amber_rounded,
              profileProvider,
              isNumber: true,
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Future<String?> _showAddUnitDialog(BuildContext context, UnitProvider unitProvider, ProfileProvider profile) async {
    final unitController = TextEditingController();
    return AppBottomSheet.show<String>(
      context: context,
      profile: profile,
      title: 'Add Unit',
      footer: SafeArea(
        child: ElevatedButton(
          onPressed: () async {
            final newUnit = unitController.text.trim();
            if (newUnit.isNotEmpty) {
              await unitProvider.addUnit(newUnit);
              if (context.mounted) Navigator.pop(context, newUnit);
            }
          },
          style: ElevatedButton.styleFrom(
            minimumSize: const Size(double.infinity, 56),
            backgroundColor: profile.themeColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: const Text('ADD UNIT', style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 8),
        child: TextField(
          controller: unitController,
          autofocus: true,
          style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            hintText: 'e.g. kg, gm, packet',
            hintStyle: TextStyle(color: profile.secondaryTextColor),
            filled: true,
            fillColor: profile.scaffoldColor,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            prefixIcon: const Icon(Icons.straighten_rounded),
          ),
        ),
      ),
    );
  }

  void _showMultiSelectBottomSheet(
    BuildContext context,
    ItemProvider itemProvider,
    ProfileProvider profile,
    List<int> initialItemIds,
    List<int> initialCategoryIds,
    Function(List<int>, List<int>) onSelectionChanged,
  ) {
    List<int> selectedItemIds = List.from(initialItemIds);
    List<int> selectedCategoryIds = List.from(initialCategoryIds);

    AppBottomSheet.show(
      context: context,
      profile: profile,
      title: "Link Targets",
      child: StatefulBuilder(
        builder: (context, setSheetState) {
          final sellingItems = itemProvider.allItems.where((i) => i.itemType == 'selling' && i.isDeleted == 0).toList();
          final categories = itemProvider.categories.where((c) => c.isDeleted == 0).toList();

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.5,
                child: DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      TabBar(
                        labelColor: profile.themeColor,
                        unselectedLabelColor: profile.secondaryTextColor,
                        indicatorColor: profile.themeColor,
                        tabs: const [
                          Tab(text: "Items"),
                          Tab(text: "Categories"),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            ListView.builder(
                              itemCount: sellingItems.length,
                              itemBuilder: (context, index) {
                                final item = sellingItems[index];
                                final isSelected = selectedItemIds.contains(item.id);
                                return CheckboxListTile(
                                  title: Text(item.name, style: TextStyle(color: profile.textColor)),
                                  value: isSelected,
                                  onChanged: (v) {
                                    setSheetState(() {
                                      if (v == true) {
                                        selectedItemIds.add(item.id!);
                                      } else {
                                        selectedItemIds.remove(item.id);
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                            ListView.builder(
                              itemCount: categories.length,
                              itemBuilder: (context, index) {
                                final cat = categories[index];
                                final isSelected = selectedCategoryIds.contains(cat.id);
                                return CheckboxListTile(
                                  title: Text(cat.name, style: TextStyle(color: profile.textColor)),
                                  value: isSelected,
                                  onChanged: (v) {
                                    setSheetState(() {
                                      if (v == true) {
                                        selectedCategoryIds.add(cat.id!);
                                      } else {
                                        selectedCategoryIds.remove(cat.id);
                                      }
                                    });
                                  },
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: ElevatedButton(
                  onPressed: () {
                    onSelectionChanged(selectedItemIds, selectedCategoryIds);
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    backgroundColor: profile.themeColor,
                  ),
                  child: const Text("DONE", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showIconPickerSheet(BuildContext context, Function(String) onSelected, String current) {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final themeColor = profile.themeColor;
    final List<String> commonIcons = ['🍔','🍕','🍟','🍦','🍩','🥤','☕','🍗','🥗','🍲','🍳','🧂','📦','💰','🏷️','🛒','🛠️'];
    AppBottomSheet.show(
      context: context, profile: profile, title: "Select Item Icon",
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LayoutBuilder(builder: (context, constraints) {
            int crossAxisCount = constraints.maxWidth > 600 ? 10 : 6;
            return GridView.builder(
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: crossAxisCount, mainAxisSpacing: 12, crossAxisSpacing: 12),
              itemCount: commonIcons.length + 1,
              itemBuilder: (context, index) {
                if (index == commonIcons.length) {
                  return GestureDetector(
                    onTap: () => _pickAndCropImage(context, onSelected),
                    child: Container(
                      decoration: BoxDecoration(color: themeColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(15), border: Border.all(color: themeColor.withValues(alpha: 0.3))),
                      child: Icon(Icons.add_a_photo_outlined, color: themeColor),
                    ),
                  );
                }
                return GestureDetector(
                  onTap: () { onSelected(commonIcons[index]); Navigator.pop(context); },
                  child: Container(
                    decoration: BoxDecoration(color: profile.scaffoldColor, borderRadius: BorderRadius.circular(15), border: Border.all(color: current == commonIcons[index] ? themeColor : Colors.transparent)),
                    alignment: Alignment.center, child: Text(commonIcons[index], style: const TextStyle(fontSize: 24)),
                  ),
                );
              },
            );
          }),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _pickAndCropImage(BuildContext context, Function(String) onSelected) async {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final String? croppedPath = await ImageHelper.pickAndCropItemIcon(context: context, themeColor: profile.themeColor);
    if (croppedPath != null) { onSelected(croppedPath); if (context.mounted) Navigator.pop(context); }
  }

  Widget _buildField(TextEditingController controller, String label, IconData icon, ProfileProvider profile, {bool isNumber = false, String? prefix, bool isCapitalize = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 12, bottom: 4),
          child: Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
              color: profile.secondaryTextColor,
              letterSpacing: 1,
            ),
          ),
        ),
        TextField(
          controller: controller,
          keyboardType: isNumber ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
          inputFormatters: isCapitalize ? [AppFormatter.capitalizeWordsFormatter] : null,
          style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold),
          decoration: InputDecoration(
            prefixText: prefix, 
            prefixIcon: Icon(icon, size: 20),
            filled: true, 
            fillColor: profile.scaffoldColor,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
          ),
        ),
      ],
    );
  }

  Widget _typeChoice(BuildContext context, String type, String label, Color color, String current, Function(String) onSelect, ProfileProvider profile) {
    bool isSelected = current == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => onSelect(type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? color : profile.scaffoldColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: isSelected ? color : (profile.isDarkMode ? Colors.white10 : Colors.grey.shade200)),
          ),
          child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: isSelected ? Colors.white : profile.secondaryTextColor, fontWeight: FontWeight.w900, fontSize: 10)),
        ),
      ),
    );
  }

  Widget _buildRecipeSection(BuildContext context, ItemProvider provider, ItemModel? item, ProfileProvider profile, StateSetter setDialogState) {
    if (item == null) return const SizedBox.shrink();
    final recipe = provider.getRecipe(item.id!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('RECIPE / BOM', style: TextStyle(color: profile.textColor, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5)),
        const SizedBox(height: 8),
        if (recipe.isEmpty)
          Text('No materials linked yet.', style: TextStyle(color: profile.secondaryTextColor, fontSize: 12))
        else
          ...recipe.map((r) {
            final material = provider.allItems.firstWhere((i) => i.id == r.materialId, orElse: () => ItemModel(name: 'Unknown', category: '', unit: '', minStock: 0, currentStock: 0));
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: profile.scaffoldColor, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Expanded(child: Text('${material.name} (${r.quantity} ${material.unit})', style: TextStyle(color: profile.textColor, fontSize: 13, fontWeight: FontWeight.bold))),
                  IconButton(
                    onPressed: () {
                      final newRecipe = List<RecipeModel>.from(recipe)..remove(r);
                      provider.saveRecipe(item.id!, newRecipe);
                      setDialogState(() {});
                    },
                    icon: const Icon(Icons.remove_circle_outline, color: Colors.red, size: 20),
                  ),
                ],
              ),
            );
          }),
        TextButton.icon(
          onPressed: () => _showAddMaterialDialog(context, provider, item.id!, profile, setDialogState),
          icon: const Icon(Icons.add_link, size: 18),
          label: const Text('LINK RAW MATERIAL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
        ),
      ],
    );
  }

  void _showAddMaterialDialog(BuildContext context, ItemProvider provider, int productId, ProfileProvider profile, StateSetter parentSetState) {
    final purchaseItems = provider.allItems.where((i) => i.itemType == 'purchase' && i.isDeleted == 0).toList();
    ItemModel? selectedMaterial;
    final qtyController = TextEditingController();

    AppBottomSheet.show(
      context: context,
      profile: profile,
      title: 'Link Raw Material',
      footer: StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: ElevatedButton(
            onPressed: () {
              if (selectedMaterial != null && qtyController.text.isNotEmpty) {
                final recipe = provider.getRecipe(productId);
                final newRecipe = List<RecipeModel>.from(recipe)
                  ..add(RecipeModel(
                    productId: productId,
                    materialId: selectedMaterial!.id!,
                    quantity: double.tryParse(qtyController.text) ?? 0,
                  ));
                provider.saveRecipe(productId, newRecipe);
                parentSetState(() {});
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(double.infinity, 56),
              backgroundColor: profile.themeColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
            child: const Text('LINK MATERIAL', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ),
      child: StatefulBuilder(
        builder: (context, setSheetState) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SELECT MATERIAL',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
                color: profile.secondaryTextColor,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: profile.scaffoldColor,
                borderRadius: BorderRadius.circular(16),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<ItemModel>(
                  value: selectedMaterial,
                  isExpanded: true,
                  hint: Text("Select Material", style: TextStyle(color: profile.secondaryTextColor)),
                  dropdownColor: profile.cardColor,
                  borderRadius: BorderRadius.circular(16),
                  items: purchaseItems.map((i) => DropdownMenuItem(
                    value: i,
                    child: Text(i.name, style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold)),
                  )).toList(),
                  onChanged: (v) => setSheetState(() => selectedMaterial = v),
                ),
              ),
            ),
            const SizedBox(height: 20),
            _buildField(
              qtyController,
              'Quantity used per unit',
              Icons.reorder_rounded,
              profile,
              isNumber: true,
              prefix: selectedMaterial != null ? '${selectedMaterial!.unit} ' : null,
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
