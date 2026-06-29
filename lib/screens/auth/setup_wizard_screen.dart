import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/item_model.dart';
import '../../models/category_model.dart';
import '../../services/template_service.dart';
import '../../providers/profile_provider.dart';
import '../../providers/item_provider.dart';
import '../../providers/category_provider.dart';
import '../../main.dart';

class SetupWizardScreen extends StatefulWidget {
  final String licenseId;
  const SetupWizardScreen({super.key, required this.licenseId});

  @override
  State<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends State<SetupWizardScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _starterPacks = [];
  Map<String, dynamic>? _selectedPack;
  
  // Selection state
  final Set<String> _selectedCategoryNames = {};
  final Set<String> _selectedItemNames = {};

  @override
  void initState() {
    super.initState();
    _loadPacks();
  }

  Future<void> _loadPacks() async {
    final packs = await TemplateService.fetchStarterPacks();
    if (mounted) {
      setState(() {
        _starterPacks = packs;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context);
    
    return Scaffold(
      backgroundColor: profile.scaffoldColor,
      appBar: AppBar(
        title: const Text("Setup Your Business"),
        backgroundColor: profile.themeColor,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _selectedPack == null 
            ? _buildPackSelection(profile)
            : _buildCustomization(profile),
      bottomNavigationBar: _selectedPack != null ? _buildBottomBar(profile) : null,
    );
  }

  Widget _buildPackSelection(ProfileProvider profile) {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(24.0),
          child: Text(
            "Select a starter pack to quickly setup your categories and items. You can customize them later.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _starterPacks.length + 1,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemBuilder: (context, index) {
              if (index == _starterPacks.length) {
                return _buildManualOption(profile);
              }
              final pack = _starterPacks[index];
              return Card(
                color: profile.cardColor,
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  title: Text(pack['packName'], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  subtitle: Text("${(pack['categories'] as List).length} Categories, ${(pack['items'] as List).length} Items"),
                  trailing: Icon(Icons.arrow_forward_ios, color: profile.themeColor),
                  onTap: () {
                    setState(() {
                      _selectedPack = pack;
                      // By default select all
                      final cats = pack['categories'] as List;
                      for (var c in cats) _selectedCategoryNames.add(c['name']);
                      final items = pack['items'] as List;
                      for (var i in items) _selectedItemNames.add(i['name']);
                    });
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildManualOption(ProfileProvider profile) {
    return Card(
      color: profile.cardColor,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: profile.themeColor.withOpacity(0.5))),
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: Icon(Icons.edit_note, color: profile.themeColor, size: 32),
        title: const Text("Skip & Setup Manually", style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text("Start with a blank database and add your own items."),
        onTap: _finalizeSetup,
      ),
    );
  }

  Widget _buildCustomization(ProfileProvider profile) {
    final categories = _selectedPack!['categories'] as List;
    final items = _selectedPack!['items'] as List;

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final cat = categories[index];
        final catItems = items.where((i) => i['category'] == cat['name']).toList();
        final isCatSelected = _selectedCategoryNames.contains(cat['name']);

        return Column(
          children: [
            CheckboxListTile(
              value: isCatSelected,
              onChanged: (val) {
                setState(() {
                  if (val == true) {
                    _selectedCategoryNames.add(cat['name']);
                    for (var i in catItems) _selectedItemNames.add(i['name']);
                  } else {
                    _selectedCategoryNames.remove(cat['name']);
                    for (var i in catItems) _selectedItemNames.remove(i['name']);
                  }
                });
              },
              title: Text(cat['name'], style: const TextStyle(fontWeight: FontWeight.bold)),
              secondary: Icon(Icons.category, color: isCatSelected ? profile.themeColor : Colors.grey),
            ),
            if (isCatSelected)
              Padding(
                padding: const EdgeInsets.only(left: 32),
                child: Wrap(
                  spacing: 8,
                  children: catItems.map((item) {
                    final isSelected = _selectedItemNames.contains(item['name']);
                    return FilterChip(
                      label: Text(item['name'], style: TextStyle(fontSize: 12, color: isSelected ? Colors.white : profile.textColor)),
                      selected: isSelected,
                      selectedColor: profile.themeColor,
                      onSelected: (val) {
                        setState(() {
                          if (val) _selectedItemNames.add(item['name']);
                          else _selectedItemNames.remove(item['name']);
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
            const Divider(),
          ],
        );
      },
    );
  }

  Widget _buildBottomBar(ProfileProvider profile) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: profile.cardColor,
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => setState(() => _selectedPack = null),
              child: const Text("BACK"),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: ElevatedButton(
              onPressed: _finalizeSetup,
              style: ElevatedButton.styleFrom(backgroundColor: profile.themeColor, foregroundColor: Colors.white),
              child: const Text("IMPORT SELECTED"),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _finalizeSetup() async {
    if (_selectedPack != null) {
      setState(() => _isLoading = true);
      
      final allCats = (_selectedPack!['categories'] as List)
          .map((c) => CategoryModel.fromMap(Map<String, dynamic>.from(c)))
          .where((c) => _selectedCategoryNames.contains(c.name))
          .toList();
          
      final allItems = (_selectedPack!['items'] as List)
          .map((i) => ItemModel.fromMap(Map<String, dynamic>.from(i)))
          .where((i) => _selectedItemNames.contains(i.name))
          .toList();

      await TemplateService.injectTemplate(
        licenseId: widget.licenseId,
        selectedItems: allItems,
        selectedCategories: allCats,
        itemProvider: Provider.of<ItemProvider>(context, listen: false),
        catProvider: Provider.of<CategoryProvider>(context, listen: false),
      );
    }

    if (mounted) {
      RestartWidget.restartApp(context);
    }
  }
}
