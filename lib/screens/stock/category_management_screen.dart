import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/category_provider.dart';
import '../../models/category_model.dart';
import '../../providers/profile_provider.dart';
import '../../providers/unit_provider.dart';
import '../../utils/app_formatter.dart';

class CategoryManagementScreen extends StatefulWidget {
  const CategoryManagementScreen({super.key});

  @override
  State<CategoryManagementScreen> createState() => _CategoryManagementScreenState();
}

class _CategoryManagementScreenState extends State<CategoryManagementScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context);
    final themeColor = profile.themeColor;

    return Scaffold(
      backgroundColor: profile.scaffoldColor,
      appBar: AppBar(
        title: const Text('MANAGE STORE', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: Colors.white)),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [themeColor.withOpacity(0.8), themeColor],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          indicatorWeight: 4,
          labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'CATEGORIES'),
            Tab(text: 'UNITS'),
          ],
        ),
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCategoryTab(context),
          _buildUnitTab(context),
        ],
      ),
    );
  }

  Widget _buildCategoryTab(BuildContext context) {
    final catProvider = Provider.of<CategoryProvider>(context);
    final profile = Provider.of<ProfileProvider>(context);
    final themeColor = profile.themeColor;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.blue.withOpacity(0.1)),
          ),
          child: Row(
            children: [
              const Icon(Icons.drag_indicator, color: Colors.blue, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Drag and drop categories to reorder them. This order will be used throughout the app.',
                  style: TextStyle(fontSize: 12, color: profile.secondaryTextColor, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: catProvider.categories.length,
            onReorder: (oldIndex, newIndex) => catProvider.reorderCategories(oldIndex, newIndex),
            itemBuilder: (context, index) {
              final cat = catProvider.categories[index];
              final isDefault = cat.name == 'General';

              return Container(
                key: ValueKey(cat.id),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: profile.cardColor,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
                  border: Border.all(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade100),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.drag_handle, color: profile.secondaryTextColor.withOpacity(0.3), size: 20),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (cat.type == 'selling' ? Colors.green : Colors.orange).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(_getIconData(cat.iconName), color: cat.type == 'selling' ? Colors.green : Colors.orange, size: 22),
                      ),
                    ],
                  ),
                  title: Text(cat.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: profile.textColor)),
                  subtitle: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: (cat.type == 'selling' ? Colors.green : Colors.orange).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          cat.type == 'selling' ? 'Selling' : 'Purchase',
                          style: TextStyle(fontSize: 10, color: cat.type == 'selling' ? Colors.green : Colors.orange, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 20, color: Colors.blue),
                        onPressed: () => _showCategoryBottomSheet(context, catProvider, profile, category: cat),
                      ),
                      if (!isDefault)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                          onPressed: () => _showDeleteWarning(context, catProvider, profile, cat),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: ElevatedButton.icon(
            onPressed: () => _showCategoryBottomSheet(context, catProvider, profile),
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('ADD NEW CATEGORY', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
            style: ElevatedButton.styleFrom(
              backgroundColor: themeColor,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 60),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUnitTab(BuildContext context) {
    final unitProvider = Provider.of<UnitProvider>(context);
    final profile = Provider.of<ProfileProvider>(context);
    final themeColor = profile.themeColor;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.orange.withOpacity(0.1)),
          ),
          child: Row(
            children: [
              const Icon(Icons.straighten, color: Colors.orange, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Add custom units like gm, kg, bori, liter, etc. These will appear in your item forms.',
                  style: TextStyle(fontSize: 12, color: profile.secondaryTextColor, height: 1.4),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: unitProvider.units.length,
            itemBuilder: (context, index) {
              final unit = unitProvider.units[index];
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: profile.cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade100),
                ),
                child: ListTile(
                  title: Text(unit.name, style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor)),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                    onPressed: () => unitProvider.deleteUnit(unit.id!),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(20),
          child: ElevatedButton.icon(
            onPressed: () => _showUnitDialog(context, unitProvider, profile),
            icon: const Icon(Icons.add_circle_outline),
            label: const Text('ADD NEW UNIT', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
            style: ElevatedButton.styleFrom(
              backgroundColor: themeColor,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 60),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              elevation: 0,
            ),
          ),
        ),
      ],
    );
  }

  void _showUnitDialog(BuildContext context, UnitProvider provider, ProfileProvider profile) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: profile.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Add New Unit', style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: profile.textColor),
          decoration: InputDecoration(
            hintText: 'e.g. kg, gm, liter',
            fillColor: profile.scaffoldColor,
            filled: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                provider.addUnit(controller.text);
                Navigator.pop(context);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: profile.themeColor),
            child: const Text('ADD', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showCategoryBottomSheet(BuildContext context, CategoryProvider provider, ProfileProvider profile, {CategoryModel? category}) {
    final themeColor = profile.themeColor;
    final nameController = TextEditingController(text: category?.name);
    String selectedIcon = category?.iconName ?? 'category';
    String selectedType = category?.type ?? 'selling';
    
    final List<Map<String, dynamic>> availableIcons = [
      {'icon': 'category', 'name': 'General'},
      {'icon': 'restaurant', 'name': 'Food'},
      {'icon': 'local_drink', 'name': 'Drinks'},
      {'icon': 'shopping_basket', 'name': 'Items'},
      {'icon': 'bolt', 'name': 'Electric'},
      {'icon': 'inventory_2', 'name': 'Stock'},
      {'icon': 'point_of_sale', 'name': 'Sales'},
      {'icon': 'handyman', 'name': 'Tools'},
      {'icon': 'kitchen', 'name': 'Cooling'},
      {'icon': 'breakfast_dining', 'name': 'Bakery'},
      {'icon': 'icecream', 'name': 'Desserts'},
      {'icon': 'coffee', 'name': 'Cafe'},
      {'icon': 'local_bar', 'name': 'Bar'},
      {'icon': 'lunch_dining', 'name': 'Fast Food'},
      {'icon': 'home', 'name': 'Home'},
      {'icon': 'work', 'name': 'Office'},
      {'icon': 'cleaning_services', 'name': 'Cleaning'},
      {'icon': 'medical_services', 'name': 'Medical'},
      {'icon': 'directions_car', 'name': 'Transport'},
      {'icon': 'local_gas_station', 'name': 'Fuel'},
      {'icon': 'grass', 'name': 'Garden'},
      {'icon': 'pets', 'name': 'Pets'},
      {'icon': 'checkroom', 'name': 'Clothes'},
      {'icon': 'fitness_center', 'name': 'Gym'},
      {'icon': 'laptop_mac', 'name': 'Electronics'},
      {'icon': 'book', 'name': 'Books'},
      {'icon': 'toys', 'name': 'Toys'},
      {'icon': 'chair', 'name': 'Furniture'},
      {'icon': 'construction', 'name': 'Hardware'},
      {'icon': 'local_shipping', 'name': 'Delivery'},
    ];

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          decoration: BoxDecoration(
            color: profile.cardColor,
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
                    decoration: BoxDecoration(color: profile.secondaryTextColor.withOpacity(0.2), borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(category == null ? 'Add Category' : 'Edit Category', 
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: profile.textColor)),
                    IconButton(onPressed: () => Navigator.pop(context), icon: Icon(Icons.close_rounded, color: profile.textColor)),
                  ],
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: nameController,
                  style: TextStyle(color: profile.textColor),
                  inputFormatters: [AppFormatter.capitalizeWordsFormatter],
                  decoration: InputDecoration(
                    labelText: 'Category Name',
                    labelStyle: TextStyle(color: profile.secondaryTextColor),
                    hintText: 'e.g. Raw Material, Cold Drinks',
                    hintStyle: TextStyle(color: profile.secondaryTextColor.withOpacity(0.5)),
                    prefixIcon: Icon(Icons.label_important_outline, color: themeColor),
                    filled: true,
                    fillColor: profile.scaffoldColor,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: themeColor, width: 2)),
                  ),
                ),
                const SizedBox(height: 20),
                Text('CATEGORY PURPOSE', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: profile.secondaryTextColor, letterSpacing: 1)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setModalState(() => selectedType = 'selling'),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: selectedType == 'selling' ? Colors.green : profile.scaffoldColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: selectedType == 'selling' ? Colors.green : (profile.isDarkMode ? Colors.white10 : Colors.grey.shade200)),
                          ),
                          child: Text('SELLING', textAlign: TextAlign.center, 
                            style: TextStyle(color: selectedType == 'selling' ? Colors.white : profile.secondaryTextColor, fontWeight: FontWeight.w900, fontSize: 12)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setModalState(() => selectedType = 'purchase'),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: selectedType == 'purchase' ? Colors.orange : profile.scaffoldColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: selectedType == 'purchase' ? Colors.orange : (profile.isDarkMode ? Colors.white10 : Colors.grey.shade200)),
                          ),
                          child: Text('PURCHASE', textAlign: TextAlign.center, 
                            style: TextStyle(color: selectedType == 'purchase' ? Colors.white : profile.secondaryTextColor, fontWeight: FontWeight.w900, fontSize: 12)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                Text('SELECT CATEGORY ICON', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: profile.secondaryTextColor, letterSpacing: 1)),
                const SizedBox(height: 12),
                
                // Dropdown-like Selector for Icons
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: profile.scaffoldColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade200),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedIcon,
                      isExpanded: true,
                      icon: Icon(Icons.keyboard_arrow_down_rounded, color: themeColor),
                      dropdownColor: profile.cardColor,
                      borderRadius: BorderRadius.circular(16),
                      items: availableIcons.map((item) {
                        return DropdownMenuItem<String>(
                          value: item['icon'],
                          child: Row(
                            children: [
                              Icon(_getIconData(item['icon']), color: themeColor, size: 20),
                              const SizedBox(width: 12),
                              Text(item['name'], style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: profile.textColor)),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) setModalState(() => selectedIcon = val);
                      },
                    ),
                  ),
                ),
                
                const SizedBox(height: 12),
                // Quick selection Wrap for some popular ones
                Wrap(
                  spacing: 10,
                  children: availableIcons.take(6).map((item) {
                    bool isSel = selectedIcon == item['icon'];
                    return GestureDetector(
                      onTap: () => setModalState(() => selectedIcon = item['icon']),
                      child: Chip(
                        label: Text(item['name'], style: TextStyle(fontSize: 10, color: isSel ? Colors.white : profile.textColor)),
                        avatar: Icon(_getIconData(item['icon']), size: 14, color: isSel ? Colors.white : themeColor),
                        backgroundColor: isSel ? themeColor : profile.scaffoldColor,
                        side: BorderSide(color: isSel ? themeColor : (profile.isDarkMode ? Colors.white10 : Colors.grey.shade200)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    );
                  }).toList(),
                ),

                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () async {
                    if (nameController.text.isNotEmpty) {
                      final newCat = CategoryModel(
                        id: category?.id,
                        name: nameController.text, 
                        iconName: selectedIcon,
                        type: selectedType,
                        displayOrder: category?.displayOrder ?? 0,
                      );
                      
                      bool success;
                      if (category == null) {
                        success = await provider.addCategory(newCat);
                      } else {
                        success = await provider.updateCategory(newCat, category.name);
                      }
                      
                      if (success) {
                        Navigator.pop(context);
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Category with this name already exists!'), backgroundColor: Colors.red),
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
                  child: Text(category == null ? 'SAVE CATEGORY' : 'UPDATE CATEGORY', 
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, letterSpacing: 1)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteWarning(BuildContext context, CategoryProvider provider, ProfileProvider profile, CategoryModel category) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: profile.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Delete Category?', style: TextStyle(color: profile.textColor)),
        content: Text('Are you sure you want to delete "${category.name}"? All items in this category will be moved to "General".', style: TextStyle(color: profile.secondaryTextColor)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          TextButton(
            onPressed: () {
              provider.deleteCategory(category.id!, category.name);
              Navigator.pop(context);
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  IconData _getIconData(String name) {
    switch (name) {
      case 'point_of_sale': return Icons.point_of_sale;
      case 'inventory_2': return Icons.inventory_2;
      case 'bolt': return Icons.bolt;
      case 'restaurant': return Icons.restaurant;
      case 'local_drink': return Icons.local_drink;
      case 'shopping_basket': return Icons.shopping_basket;
      case 'handyman': return Icons.handyman;
      case 'kitchen': return Icons.kitchen;
      case 'breakfast_dining': return Icons.breakfast_dining;
      case 'icecream': return Icons.icecream;
      case 'coffee': return Icons.coffee;
      case 'local_bar': return Icons.local_bar;
      case 'lunch_dining': return Icons.lunch_dining;
      case 'home': return Icons.home;
      case 'work': return Icons.work;
      case 'cleaning_services': return Icons.cleaning_services;
      case 'medical_services': return Icons.medical_services;
      case 'directions_car': return Icons.directions_car;
      case 'local_gas_station': return Icons.local_gas_station;
      case 'grass': return Icons.grass;
      case 'pets': return Icons.pets;
      case 'checkroom': return Icons.checkroom;
      case 'fitness_center': return Icons.fitness_center;
      case 'laptop_mac': return Icons.laptop_mac;
      case 'book': return Icons.book;
      case 'toys': return Icons.toys;
      case 'chair': return Icons.chair;
      case 'construction': return Icons.construction;
      case 'local_shipping': return Icons.local_shipping;
      default: return Icons.category;
    }
  }
}
