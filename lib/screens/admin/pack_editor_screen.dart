import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/profile_provider.dart';
import '../../services/template_service.dart';
import '../../models/category_model.dart';
import '../../models/item_model.dart';
import '../../core/widgets/app_bottom_sheet.dart';

class PackEditorScreen extends StatefulWidget {
  final Map<String, dynamic>? pack;
  const PackEditorScreen({super.key, this.pack});

  @override
  State<PackEditorScreen> createState() => _PackEditorScreenState();
}

class _PackEditorScreenState extends State<PackEditorScreen> {
  late TextEditingController _nameController;
  List<CategoryModel> categories = [];
  List<ItemModel> items = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.pack?['packName'] ?? '');
    if (widget.pack != null) {
      categories = (widget.pack!['categories'] as List)
          .map((c) => CategoryModel.fromMap(Map<String, dynamic>.from(c)))
          .toList();
      items = (widget.pack!['items'] as List)
          .map((i) => ItemModel.fromMap(Map<String, dynamic>.from(i)))
          .toList();
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context);
    final appBarColor = ThemeData.estimateBrightnessForColor(profile.themeColor) == Brightness.dark
        ? Colors.white
        : Colors.black;
    
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: profile.scaffoldColor,
        appBar: AppBar(
          title: Text(widget.pack == null ? "Create Starter Pack" : "Edit Pack", style: const TextStyle(fontWeight: FontWeight.bold)),
          backgroundColor: profile.themeColor,
          foregroundColor: appBarColor,
          actions: [
            if (_isSaving)
              Center(child: Padding(padding: const EdgeInsets.only(right: 16), child: CircularProgressIndicator(color: appBarColor, strokeWidth: 2)))
            else
              IconButton(
                icon: const Icon(Icons.check_circle_outline_rounded, size: 28),
                onPressed: _savePack,
                tooltip: "Save Pack",
              ),
            const SizedBox(width: 8),
          ],
          bottom: TabBar(
            tabs: const [
              Tab(text: "CATEGORIES", icon: Icon(Icons.category_outlined)),
              Tab(text: "ITEMS", icon: Icon(Icons.inventory_2_outlined)),
            ],
            indicatorColor: appBarColor,
            labelColor: appBarColor,
            unselectedLabelColor: appBarColor.withValues(alpha: 0.6),
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          ),
        ),
        body: Column(
          children: [
            _buildNameField(profile),
            Expanded(
              child: TabBarView(
                children: [
                  _buildCategoryList(profile),
                  _buildItemList(profile),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNameField(ProfileProvider profile) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: profile.cardColor,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: TextField(
        controller: _nameController,
        style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold, fontSize: 18),
        decoration: InputDecoration(
          labelText: "TEMPLATE NAME",
          labelStyle: TextStyle(color: profile.themeColor, letterSpacing: 1.2, fontSize: 12, fontWeight: FontWeight.bold),
          hintText: "e.g. Fine Dine Restaurant, Grocery Store...",
          prefixIcon: Icon(Icons.drive_file_rename_outline_rounded, color: profile.themeColor),
          filled: true,
          fillColor: profile.scaffoldColor,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
        ),
      ),
    );
  }

  Widget _buildCategoryList(ProfileProvider profile) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("CATEGORIES (${categories.length})", style: TextStyle(fontWeight: FontWeight.w900, color: profile.secondaryTextColor, fontSize: 12)),
              TextButton.icon(
                onPressed: _addCategory,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text("ADD MULTIPLE"),
                style: TextButton.styleFrom(foregroundColor: profile.themeColor),
              )
            ],
          ),
        ),
        Expanded(
          child: categories.isEmpty
              ? _buildEmptyState(Icons.category_outlined, "No Categories Added")
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: categories.length,
                  itemBuilder: (context, i) => _buildCategoryCard(i, profile),
                ),
        ),
      ],
    );
  }

  Widget _buildCategoryCard(int index, ProfileProvider profile) {
    final cat = categories[index];
    return Card(
      color: profile.cardColor,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: cat.type == 'selling' ? Colors.green.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
          child: Icon(cat.type == 'selling' ? Icons.sell_rounded : Icons.shopping_bag_rounded, 
            color: cat.type == 'selling' ? Colors.green : Colors.orange, size: 20),
        ),
        title: Text(cat.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(cat.type.toUpperCase(), style: TextStyle(fontSize: 10, color: profile.secondaryTextColor, fontWeight: FontWeight.bold)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Colors.blue, size: 20),
              onPressed: () => _editCategory(index),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
              onPressed: () => setState(() => categories.removeAt(index)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemList(ProfileProvider profile) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text("ITEMS (${items.length})", style: TextStyle(fontWeight: FontWeight.w900, color: profile.secondaryTextColor, fontSize: 12)),
              TextButton.icon(
                onPressed: _addItem,
                icon: const Icon(Icons.add_circle_outline),
                label: const Text("ADD NEW ITEM"),
                style: TextButton.styleFrom(foregroundColor: profile.themeColor),
              )
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? _buildEmptyState(Icons.inventory_2_outlined, "No Items Added")
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _buildItemCard(i, profile),
                ),
        ),
      ],
    );
  }

  Widget _buildItemCard(int index, ProfileProvider profile) {
    final item = items[index];
    return Card(
      color: profile.cardColor,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text("${item.category} • ₹${item.price} • ${item.unit}", style: const TextStyle(fontSize: 11)),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
             IconButton(
              icon: const Icon(Icons.edit_outlined, color: Colors.blue, size: 20),
              onPressed: () => _editItem(index),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 20),
              onPressed: () => setState(() => items.removeAt(index)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(IconData icon, String msg) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: Colors.grey.withValues(alpha: 0.3)),
          const SizedBox(height: 12),
          Text(msg, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  void _addCategory() => _showCategoryDialog();
  void _editCategory(int index) => _showCategoryDialog(index: index);

  void _showCategoryDialog({int? index}) {
    final existing = index != null ? categories[index] : null;
    final nameC = TextEditingController(text: existing?.name);
    String type = existing?.type ?? 'selling';
    
    AppBottomSheet.show(
      context: context,
      profile: Provider.of<ProfileProvider>(context, listen: false),
      title: index == null ? "Add Categories" : "Edit Category",
      child: StatefulBuilder(
        builder: (context, setSheetState) => Column(
          children: [
            if (index == null)
              const Text("You can add multiple categories separated by comma (,)", 
                style: TextStyle(fontSize: 11, color: Colors.grey)),
            const SizedBox(height: 16),
            TextField(
              controller: nameC,
              autofocus: true,
              decoration: InputDecoration(
                labelText: "Category Name(s)",
                hintText: index == null ? "Burger, Pizza, Drinks..." : "Category Name",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text("Selling"),
                    value: 'selling',
                    groupValue: type,
                    onChanged: (v) => setSheetState(() => type = v!),
                  ),
                ),
                Expanded(
                  child: RadioListTile<String>(
                    title: const Text("Purchase"),
                    value: 'purchase',
                    groupValue: type,
                    onChanged: (v) => setSheetState(() => type = v!),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () {
                if (nameC.text.isEmpty) return;
                
                setState(() {
                  if (index != null) {
                    categories[index] = categories[index].copyWith(name: nameC.text, type: type);
                  } else {
                    final names = nameC.text.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty);
                    for (var n in names) {
                      if (!categories.any((c) => c.name.toLowerCase() == n.toLowerCase())) {
                        categories.add(CategoryModel(name: n, type: type));
                      }
                    }
                  }
                });
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                minimumSize: const Size(double.infinity, 50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(index == null ? "ADD TO TEMPLATE" : "UPDATE CATEGORY", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _addItem() => _showItemDialog();
  void _editItem(int index) => _showItemDialog(index: index);

  void _showItemDialog({int? index}) {
    if (categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Add at least one category first!")));
      return;
    }
    
    final existing = index != null ? items[index] : null;
    final nameC = TextEditingController(text: existing?.name);
    final priceC = TextEditingController(text: existing?.price?.toString());
    final unitC = TextEditingController(text: existing?.unit ?? 'pcs');
    String category = existing?.category ?? categories.first.name;
    String type = existing?.itemType ?? 'selling';

    AppBottomSheet.show(
      context: context,
      profile: Provider.of<ProfileProvider>(context, listen: false),
      title: index == null ? "Add Item" : "Edit Item",
      child: StatefulBuilder(
        builder: (context, setSheetState) => SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: nameC,
                decoration: const InputDecoration(labelText: "Item Name", prefixIcon: Icon(Icons.shopping_basket_outlined)),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: priceC,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d*'))],
                      decoration: const InputDecoration(labelText: "Default Price", prefixIcon: Icon(Icons.currency_rupee_rounded)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: unitC,
                      decoration: const InputDecoration(labelText: "Unit (e.g. pcs, kg)", prefixIcon: Icon(Icons.scale_rounded)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: categories.any((c) => c.name == category) ? category : categories.first.name,
                decoration: const InputDecoration(labelText: "Category", prefixIcon: Icon(Icons.category_rounded)),
                items: categories.map((e) => DropdownMenuItem(value: e.name, child: Text(e.name))).toList(),
                onChanged: (v) => category = v!,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  if (nameC.text.isEmpty) return;
                  final newItem = ItemModel(
                    name: nameC.text,
                    category: category,
                    price: double.tryParse(priceC.text) ?? 0,
                    unit: unitC.text,
                    minStock: 0,
                    currentStock: 0,
                    itemType: categories.firstWhere((c) => c.name == category).type,
                  );
                  setState(() {
                    if (index == null) {
                      items.add(newItem);
                    } else {
                      items[index] = newItem;
                    }
                  });
                  Navigator.pop(context);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(index == null ? "ADD ITEM" : "UPDATE ITEM", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _savePack() async {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter a pack name")));
      return;
    }
    if (categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Add at least one category")));
      return;
    }

    setState(() => _isSaving = true);
    try {
      await TemplateService.saveStarterPack(_nameController.text, categories, items);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Starter Pack Saved Successfully!"), backgroundColor: Colors.green));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Save Error: $e")));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
