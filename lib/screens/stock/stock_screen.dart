import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter/rendering.dart';
import '../../providers/profile_provider.dart';
import '../../providers/item_provider.dart';
import '../../providers/category_provider.dart';
import '../../models/item_model.dart';
import '../items/item_management_screen.dart';
import 'category_management_screen.dart';
import '../../utils/app_formatter.dart';

class StockScreen extends StatefulWidget {
  const StockScreen({super.key});

  @override
  State<StockScreen> createState() => _StockScreenState();
}

class _StockScreenState extends State<StockScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _isBottomNavVisible = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (_scrollController.position.userScrollDirection == ScrollDirection.reverse) {
        if (_isBottomNavVisible) setState(() => _isBottomNavVisible = false);
      } else if (_scrollController.position.userScrollDirection == ScrollDirection.forward) {
        if (!_isBottomNavVisible) setState(() => _isBottomNavVisible = true);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final itemProvider = Provider.of<ItemProvider>(context);
    final catProvider = Provider.of<CategoryProvider>(context);
    final profileProvider = Provider.of<ProfileProvider>(context);
    final themeColor = profileProvider.themeColor;

    // Logic: Items are already sorted A-Z from ItemProvider getter
    final sortedItems = itemProvider.items;

    return Scaffold(
      backgroundColor: profileProvider.scaffoldColor,
      appBar: AppBar(
        title: const Text('INVENTORY & STOCK', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white)),
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
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_suggest, color: Colors.white),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoryManagementScreen())),
            tooltip: 'Manage Categories',
          ),
        ],
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: sortedItems.isEmpty
          ? _buildEmptyState(context, profileProvider)
          : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: sortedItems.length,
              itemBuilder: (context, index) {
                final item = sortedItems[index];
                final isLow = item.currentStock <= item.minStock;
                
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: profileProvider.cardColor,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
                    border: Border.all(color: isLow ? Colors.red.withOpacity(0.5) : (profileProvider.isDarkMode ? Colors.white10 : Colors.grey.shade100)),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    title: Text(item.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: profileProvider.textColor)),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.category, style: TextStyle(fontSize: 12, color: profileProvider.secondaryTextColor)),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isLow ? Colors.red.withOpacity(0.1) : Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isLow ? 'LOW STOCK' : 'IN STOCK',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isLow ? Colors.red : Colors.green),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text('Min: ${item.minStock} ${item.unit}', style: TextStyle(fontSize: 11, color: profileProvider.secondaryTextColor)),
                          ],
                        ),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${item.currentStock}', 
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: isLow ? Colors.red : profileProvider.textColor)),
                        Text(item.unit, style: TextStyle(fontSize: 12, color: profileProvider.secondaryTextColor)),
                      ],
                    ),
                    onTap: () => _showItemActions(context, itemProvider, item, profileProvider),
                  ),
                );
              },
            ),
      bottomNavigationBar: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: _isBottomNavVisible ? 95 : 0,
        child: _isBottomNavVisible ? Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: profileProvider.cardColor,
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, -5))],
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: SafeArea(
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: themeColor,
                foregroundColor: Colors.white,
                minimumSize: const Size(double.infinity, 55),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 0,
              ),
              onPressed: () => _showCategoryPicker(context, catProvider, profileProvider),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_circle_outline),
                  SizedBox(width: 10),
                  Text('ADD NEW ITEM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
            ),
          ),
        ) : const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ProfileProvider profile) {
    final catProvider = Provider.of<CategoryProvider>(context, listen: false);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 80, color: profile.secondaryTextColor.withOpacity(0.2)),
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
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
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
                decoration: BoxDecoration(color: profile.secondaryTextColor.withOpacity(0.2), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(item.name.toUpperCase(), style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: profile.textColor, letterSpacing: 1)),
            const SizedBox(height: 24),
            _actionTile(Icons.edit_note, 'Quick Stock Update', Colors.blue, profile, () {
              Navigator.pop(context);
              _showUpdateStockBottomSheet(context, provider, item, profile);
            }),
            _actionTile(Icons.edit, 'Edit Item Details', Colors.orange, profile, () {
              Navigator.pop(context);
              Navigator.push(context, MaterialPageRoute(builder: (_) => ItemManagementScreen(category: item.category, editItem: item)));
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
      leading: CircleAvatar(backgroundColor: color.withOpacity(0.1), child: Icon(icon, color: color, size: 20)),
      title: Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor, fontSize: 14)),
      trailing: Icon(Icons.arrow_forward_ios_rounded, size: 12, color: profile.secondaryTextColor.withOpacity(0.3)),
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
                decoration: BoxDecoration(color: profile.secondaryTextColor.withOpacity(0.2), borderRadius: BorderRadius.circular(2)),
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
                        backgroundColor: themeColor.withOpacity(0.1),
                        child: Icon(Icons.folder_outlined, color: themeColor, size: 20),
                      ),
                      title: Text(cat.name, style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor, fontSize: 14)),
                      trailing: Icon(Icons.chevron_right, color: profile.secondaryTextColor),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => ItemManagementScreen(category: cat.name)));
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
    final stockController = TextEditingController(text: item.currentStock.toString());
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
                decoration: BoxDecoration(color: profile.secondaryTextColor.withOpacity(0.2), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text('Update Stock: ${item.name}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: profile.textColor)),
            const SizedBox(height: 24),
            TextField(
              controller: stockController,
              inputFormatters: [AppFormatter.capitalizeWordsFormatter],
              style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold),
              onTap: () {
                if (stockController.text == '0' || stockController.text == '0.0') {
                  stockController.clear();
                }
              },
              decoration: InputDecoration(
                labelText: 'Update Quantity / Name', 
                labelStyle: TextStyle(color: profile.secondaryTextColor),
                prefixIcon: Icon(Icons.inventory_2_outlined, color: profile.themeColor),
                filled: true,
                fillColor: profile.scaffoldColor,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: profile.themeColor, width: 2)),
              ),
              keyboardType: TextInputType.text, // Changed to text to support capitalization testing if needed, or keep as number
              autofocus: true,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
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
              provider.deleteItem(item.id!); 
              Navigator.pop(context); 
            }, 
            child: const Text('DELETE', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold))
          ),
        ],
      ),
    );
  }
}
