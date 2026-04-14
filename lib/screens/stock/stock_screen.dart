import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/category_model.dart';
import '../../providers/profile_provider.dart';
import '../../providers/item_provider.dart';
import '../../providers/category_provider.dart';
import '../../providers/purchase_reminder_provider.dart';
import '../../models/item_model.dart';
import '../items/item_management_screen.dart';
import '../purchase_reminders/purchase_reminder_screen.dart';
import 'category_management_screen.dart';

class StockScreen extends StatefulWidget {
  final String? initialCategory;
  final bool filterLowStock;

  const StockScreen({
    super.key,
    this.initialCategory,
    this.filterLowStock = false
  });

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  String? _selectedCategory;
  String _searchQuery = '';
  bool _onlyShowLowStock = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedCategory = widget.initialCategory;
    _onlyShowLowStock = widget.filterLowStock;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final itemProvider = Provider.of<ItemProvider>(context);
    final catProvider = Provider.of<CategoryProvider>(context);
    final profileProvider = Provider.of<ProfileProvider>(context);
    final reminderProvider = Provider.of<PurchaseReminderProvider>(context);
    final themeColor = profileProvider.themeColor;

    return PopScope(
      canPop: _selectedCategory == null && _searchQuery.isEmpty && !_onlyShowLowStock,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        setState(() {
          if (_selectedCategory != null) {
            _selectedCategory = null;
          } else {
            _searchQuery = '';
            _searchController.clear();
            _onlyShowLowStock = false;
          }
        });
      },
      child: Scaffold(
        backgroundColor: profileProvider.scaffoldColor,
        appBar: _selectedCategory == null ? null : AppBar(
          title: Text(_selectedCategory!.toUpperCase(),
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.white)),
          flexibleSpace: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [themeColor.withValues(alpha: 0.8), themeColor],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              setState(() {
                _selectedCategory = null;
              });
            },
          ),
          centerTitle: true,
          actions: [
            IconButton(
              icon: Icon(_onlyShowLowStock ? Icons.filter_list_off : Icons.filter_list, color: Colors.white),
              onPressed: () => setState(() => _onlyShowLowStock = !_onlyShowLowStock),
              tooltip: 'Low Stock Filter',
            ),
          ],
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: SafeArea(
          child: Column(
            children: [
              _buildSearchBar(profileProvider),
              if (reminderProvider.reminders.any((r) => r.status == 'pending'))
                _buildReminderBanner(reminderProvider, profileProvider),
              Expanded(
                child: _selectedCategory == null && _searchQuery.isEmpty && !_onlyShowLowStock
                  ? _buildCategoryList(catProvider, itemProvider, profileProvider)
                  : _buildFilteredItemList(itemProvider, profileProvider),
              ),
              _buildBottomActionBar(profileProvider, catProvider),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(ProfileProvider profile) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: profile.cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (v) => setState(() => _searchQuery = v),
        style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold),
        decoration: InputDecoration(
          hintText: 'Search items by name...',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchQuery.isNotEmpty ? IconButton(
            icon: const Icon(Icons.clear, size: 18),
            onPressed: () {
              _searchController.clear();
              setState(() => _searchQuery = '');
            },
          ) : null,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          filled: true,
          fillColor: profile.scaffoldColor,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildReminderBanner(PurchaseReminderProvider provider, ProfileProvider profile) {
    final pendingCount = provider.reminders.where((r) => r.status == 'pending').length;
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (c) => const PurchaseReminderScreen())),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: profile.themeColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: profile.themeColor.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(Icons.shopping_cart_checkout_rounded, color: profile.themeColor, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'You have $pendingCount planned purchases',
                style: TextStyle(fontWeight: FontWeight.bold, color: profile.themeColor, fontSize: 13),
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: profile.themeColor),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActionBar(ProfileProvider profile, CategoryProvider catProvider) {
    final itemProvider = Provider.of<ItemProvider>(context, listen: false);
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      decoration: BoxDecoration(
        color: profile.cardColor,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5))],
      ),
      child: Row(
        children: [
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () => _showCategoryPicker(context, catProvider, profile),
              icon: const Icon(Icons.add_circle_outline, size: 16),
              label: const Text('ADD NEW ITEM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              style: ElevatedButton.styleFrom(
                backgroundColor: profile.themeColor,
                foregroundColor: Colors.white,
                minimumSize: const Size(0, 42),
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(
            onPressed: () => _showStockSettingsBottomSheet(context, itemProvider, catProvider, profile),
            icon: Icon(Icons.tune_rounded, color: profile.themeColor, size: 22),
            style: IconButton.styleFrom(
              backgroundColor: profile.themeColor.withValues(alpha: 0.1),
              padding: const EdgeInsets.all(10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  void _showStockSettingsBottomSheet(BuildContext context, ItemProvider itemProvider, CategoryProvider catProvider, ProfileProvider profile) {
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
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(color: profile.secondaryTextColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text('STOCK SETTINGS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: profile.textColor, letterSpacing: 1.2)),
            const SizedBox(height: 24),
            _actionTile(Icons.playlist_add_check_rounded, 'Purchase Planning List', profile.themeColor, profile, () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const PurchaseReminderScreen()));
            }),
            _actionTile(Icons.category_outlined, 'Manage Categories', Colors.orange, profile, () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoryManagementScreen()));
            }),
            _actionTile(Icons.notification_important_outlined, 'Low Stock Alert Settings', Colors.purple, profile, () {
              Navigator.pop(context);
              _showLowStockSettings(context, itemProvider, catProvider, profile);
            }),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryList(CategoryProvider catProvider, ItemProvider itemProvider, ProfileProvider profile) {
    final List<String> categories = catProvider.categories.map((c) => c.name).toList();
    categories.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    final uncategorizedItems = itemProvider.getItemsByCategory('Uncategorized');
    final hasUncategorized = uncategorizedItems.isNotEmpty;

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: categories.length + (hasUncategorized ? 1 : 0),
      itemBuilder: (context, index) {
        final isUncategorized = hasUncategorized && index == categories.length;
        final catName = isUncategorized ? 'Uncategorized' : categories[index];
        final items = itemProvider.getItemsByCategory(catName);
        final lowStockCount = items.where((i) => itemProvider.isLowStock(i)).length;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: profile.cardColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
            border: Border.all(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade100),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            leading: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: (isUncategorized ? Colors.grey : profile.themeColor).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(14)),
              child: Icon(isUncategorized ? Icons.help_outline_rounded : Icons.folder_rounded, color: isUncategorized ? Colors.grey : profile.themeColor, size: 24),
            ),
            title: Text(catName, style: TextStyle(fontWeight: FontWeight.w900, color: profile.textColor, fontSize: 15)),
            subtitle: Text('${items.length} Items Total', style: TextStyle(fontSize: 12, color: profile.secondaryTextColor)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (lowStockCount > 0)
                  Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                    child: Text('$lowStockCount LOW', style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 10)),
                  ),
                Icon(Icons.chevron_right, color: profile.secondaryTextColor.withValues(alpha: 0.5)),
              ],
            ),
            onTap: () => setState(() => _selectedCategory = catName),
          ),
        );
      },
    );
  }

  Widget _buildFilteredItemList(ItemProvider itemProvider, ProfileProvider profile) {
    final filteredItems = itemProvider.allItems.where((item) {
      bool matchCategory = _selectedCategory == null ||
          (_selectedCategory == 'Uncategorized'
              ? itemProvider.getItemsByCategory('Uncategorized').contains(item)
              : item.category == _selectedCategory);

      bool matchSearch = _searchQuery.isEmpty || item.name.toLowerCase().contains(_searchQuery.toLowerCase());
      bool matchLowStock = !_onlyShowLowStock || itemProvider.isLowStock(item);

      return matchCategory && matchSearch && matchLowStock;
    }).toList();

    if (filteredItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 60, color: profile.secondaryTextColor.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('No items found', style: TextStyle(color: profile.secondaryTextColor, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredItems.length,
      itemBuilder: (context, index) {
        final item = filteredItems[index];
        final isLow = itemProvider.isLowStock(item);

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: profile.cardColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10)],
            border: Border.all(color: isLow ? Colors.red.withValues(alpha: 0.5) : (profile.isDarkMode ? Colors.white10 : Colors.grey.shade100), width: isLow ? 2 : 1),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            title: Text(item.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: profile.textColor)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isLow ? Colors.red.withValues(alpha: 0.1) : Colors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        isLow ? 'LOW STOCK' : 'IN STOCK',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isLow ? Colors.red : Colors.green),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text('Min: ${item.minStock} ${item.unit}', style: TextStyle(fontSize: 11, color: profile.secondaryTextColor)),
                  ],
                ),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('${item.currentStock % 1 == 0 ? item.currentStock.toInt() : item.currentStock}',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isLow ? Colors.red : profile.textColor)),
                Text(item.unit, style: TextStyle(fontSize: 12, color: profile.secondaryTextColor)),
              ],
            ),
            onTap: () => _showItemActions(context, itemProvider, item, profile),
          ),
        );
      },
    );
  }

  void _showLowStockSettings(BuildContext context, ItemProvider itemProvider, CategoryProvider catProvider, ProfileProvider profile) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          height: MediaQuery.of(context).size.height * 0.75,
          decoration: BoxDecoration(
            color: profile.cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(color: profile.secondaryTextColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Text('LOW STOCK ALERTS', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: profile.textColor, letterSpacing: 1)),
              const SizedBox(height: 8),
              Text('Toggle alerts for entire categories or specific items.', style: TextStyle(color: profile.secondaryTextColor, fontSize: 12)),
              const SizedBox(height: 24),
              Expanded(
                child: ListView.builder(
                  itemCount: catProvider.categories.length,
                  itemBuilder: (context, index) {
                    final cat = catProvider.categories[index];
                    final catItems = itemProvider.getItemsByCategory(cat.name);
                    final allOn = catItems.isNotEmpty && catItems.every((i) => i.lowStockAlert == 1);

                    return Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        title: Text(cat.name, style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor)),
                        subtitle: Text('${catItems.length} items', style: TextStyle(fontSize: 11, color: profile.secondaryTextColor)),
                        trailing: Switch(
                          value: allOn,
                          activeColor: profile.themeColor,
                          onChanged: (val) async {
                            await itemProvider.toggleCategoryAlerts(cat.name, val);
                            setModalState(() {});
                          },
                        ),
                        children: catItems.map((item) => ListTile(
                          contentPadding: const EdgeInsets.only(left: 16),
                          title: Text(item.name, style: TextStyle(fontSize: 14, color: profile.textColor)),
                          subtitle: Text('Current: ${item.currentStock % 1 == 0 ? item.currentStock.toInt() : item.currentStock} ${item.unit}', style: const TextStyle(fontSize: 11)),
                          trailing: Switch(
                            value: item.lowStockAlert == 1,
                            activeColor: profile.themeColor,
                            onChanged: (val) async {
                              await itemProvider.toggleLowStockAlert(item.id!, val);
                              setModalState(() {});
                            },
                          ),
                        )).toList(),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ProfileProvider profile) {
    final catProvider = Provider.of<CategoryProvider>(context, listen: false);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 80, color: profile.secondaryTextColor.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text('Inventory is empty', style: TextStyle(color: profile.secondaryTextColor, fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: profile.themeColor, elevation: 0),
            onPressed: () => _showCategoryPicker(context, catProvider, profile),
            child: const Text('Add Your First Item'),
          )
        ],
      ),
    );
  }

  void _showItemActions(BuildContext context, ItemProvider provider, ItemModel item, ProfileProvider profile) {
    CategoryModel? cat;
    try {
      cat = Provider.of<CategoryProvider>(context, listen: false).getCategoryByName(item.category);
    } catch (_) {}

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
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
                decoration: BoxDecoration(color: profile.secondaryTextColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 24),
            if (cat == null || cat.useCategoryStock == 0)
              _actionTile(Icons.edit_note, 'Quick Stock Update', Colors.blue, profile, () {
                Navigator.pop(context);
                _showUpdateStockBottomSheet(context, provider, item, profile);
              }),
            _actionTile(item.lowStockAlert == 1 ? Icons.notifications_off_outlined : Icons.notifications_active_outlined,
              item.lowStockAlert == 1 ? 'Disable Low Stock Alert' : 'Enable Low Stock Alert',
              Colors.purple, profile, () {
              provider.toggleLowStockAlert(item.id!, item.lowStockAlert == 0);
              Navigator.pop(context);
            }),
            _actionTile(Icons.edit, 'Edit Item Details', Colors.orange, profile, () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (c) => ItemManagementScreen(category: item.category, editItem: item)));
            }),
            _actionTile(Icons.delete_outline, 'Delete Item', Colors.red, profile, () {
              Navigator.pop(context);
              _showDeleteConfirm(context, provider, item, profile);
            }),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _actionTile(IconData icon, String title, Color color, ProfileProvider profile, VoidCallback onTap) {
    return ListTile(
      leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.1), child: Icon(icon, color: color, size: 20)),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor, fontSize: 14)),
      trailing: Icon(Icons.arrow_forward_ios_rounded, size: 12, color: profile.secondaryTextColor.withValues(alpha: 0.3)),
      onTap: onTap,
    );
  }

  void _showCategoryPicker(BuildContext context, CategoryProvider catProvider, ProfileProvider profile) {
    final themeColor = profile.themeColor;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
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
                decoration: BoxDecoration(color: profile.secondaryTextColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('SELECT CATEGORY', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: profile.textColor, letterSpacing: 1)),
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoryManagementScreen()));
                  },
                  icon: const Icon(Icons.settings_suggest, size: 18),
                  label: const Text('MANAGE', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: TextButton.styleFrom(foregroundColor: themeColor),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: catProvider.categories.length,
                itemBuilder: (context, index) {
                  final cat = catProvider.categories[index];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: profile.scaffoldColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade100),
                    ),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: themeColor.withValues(alpha: 0.1),
                        child: Icon(Icons.folder_outlined, color: themeColor, size: 20),
                      ),
                      title: Text(cat.name, style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor, fontSize: 14)),
                      trailing: Icon(Icons.chevron_right, color: profile.secondaryTextColor),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (c) => ItemManagementScreen(category: cat.name)));
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showUpdateStockBottomSheet(BuildContext context, ItemProvider provider, ItemModel item, ProfileProvider profile) {
    final stockController = TextEditingController();
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(color: profile.secondaryTextColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text('Update Stock: ${item.name}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: profile.textColor)),
            const SizedBox(height: 24),
            TextField(
              controller: stockController,
              style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                labelText: 'Update Quantity',
                hintText: 'Current: ${item.currentStock % 1 == 0 ? item.currentStock.toInt() : item.currentStock}',
                hintStyle: TextStyle(color: profile.secondaryTextColor.withValues(alpha: 0.4)),
                labelStyle: TextStyle(color: profile.secondaryTextColor),
                prefixIcon: Icon(Icons.inventory_2_outlined, color: profile.themeColor),
                filled: true,
                fillColor: profile.scaffoldColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: profile.themeColor, width: 2)),
              ),
              keyboardType: TextInputType.number,
              autofocus: true,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                if (stockController.text.isEmpty) {
                  Navigator.pop(context);
                  return;
                }
                final newVal = double.tryParse(stockController.text) ?? item.currentStock;
                provider.updateStock(item.id!, newVal);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: profile.themeColor,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 60),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                elevation: 0,
              ),
              child: const Text('UPDATE STOCK LEVEL', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1)),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirm(BuildContext context, ItemProvider provider, ItemModel item, ProfileProvider profile) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: profile.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text('Delete Item?', style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold)),
        content: Text('Are you sure you want to remove "${item.name}" from inventory?', style: TextStyle(color: profile.secondaryTextColor)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          TextButton(
            onPressed: () {
              provider.softDeleteItem(item.id!);
              Navigator.pop(context);
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
          ),
        ],
      ),
    );
  }
}
