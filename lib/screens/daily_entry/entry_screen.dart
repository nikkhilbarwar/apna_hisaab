import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/item_provider.dart';
import '../../models/item_model.dart';
import '../../providers/category_provider.dart';
import '../../providers/profile_provider.dart';
import '../../models/transaction_model.dart';
import '../../models/cart_item.dart';
import '../stock/category_management_screen.dart';
import 'cart_details_screen.dart';

class EntryScreen extends StatefulWidget {
  final TransactionModel? transaction;
  final String? initialType; // 'sale', 'purchase', or 'expense'
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

class _EntryScreenState extends State<EntryScreen> {
  late String _type;
  late String _selectedCategory;
  late DateTime _selectedDate; // New: Date tracking
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  final List<CartItem> _cart = [];

  @override
  void initState() {
    super.initState();
    _type = widget.transaction?.type ?? widget.initialType ?? 'sale';
    _selectedDate = widget.transaction?.date ?? DateTime.now(); // Init with current or tx date
    
    // Default to virtual "All" categories
    _selectedCategory = widget.transaction?.category ?? widget.initialCategory ?? 
        (_type == 'sale' ? 'All Sales' : (_type == 'purchase' ? 'All Purchases' : 'All Expenses'));
    
    if (widget.transaction != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _rebuildCartFromTransaction();
      });
    }
  }

  void _rebuildCartFromTransaction() {
    if (widget.transaction == null) return;
    final itemProvider = Provider.of<ItemProvider>(context, listen: false);
    
    final items = widget.transaction!.parsedItems;
    for (var it in items) {
      try {
        final item = itemProvider.items.firstWhere((element) => element.name.trim().toLowerCase() == it['name']?.trim().toLowerCase());
        setState(() {
          _cart.add(CartItem(
            item: item, 
            quantity: double.tryParse(it['qty'] ?? '1') ?? 1, 
            price: double.tryParse(it['price'] ?? '0') ?? (item.price ?? 0), 
            variant: it['variant'] ?? 'Full', 
            unit: item.unit
          ));
        });
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _addItemToCart(ItemModel item, {String variant = 'Full'}) {
    double price = variant == 'Half' ? (item.halfPrice ?? 0) : (item.price ?? 0);
    String unit = variant == 'Half' ? (item.halfUnit ?? item.unit) : (item.fullUnit ?? item.unit);

    setState(() {
      final existingIndex = _cart.indexWhere((c) => c.item.id == item.id && c.variant == variant);
      if (existingIndex != -1) {
        _cart[existingIndex].quantity++;
      } else {
        _cart.add(CartItem(item: item, quantity: 1, price: price, variant: variant, unit: unit));
      }
    });
  }

  void _removeItemFromCart(ItemModel item) {
    setState(() {
      final existingIndex = _cart.lastIndexWhere((c) => c.item.id == item.id);
      if (existingIndex != -1) {
        if (_cart[existingIndex].quantity > 1) {
          _cart[existingIndex].quantity--;
        } else {
          _cart.removeAt(existingIndex);
        }
      }
    });
  }

  void _showVariantPicker(ItemModel item) {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    showModalBottomSheet(
      context: context,
      backgroundColor: profile.cardColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: profile.themeColor.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
              child: Row(
                children: [
                  Icon(Icons.restaurant_menu_rounded, color: profile.themeColor),
                  const SizedBox(width: 16),
                  Expanded(child: Text(item.name, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: profile.textColor))),
                ],
              ),
            ),
            const SizedBox(height: 24),
            _variantTile(
              profile: profile,
              title: 'Full Portion',
              sub: item.fullUnit ?? '1 Plate',
              price: '${profile.currencySymbol}${item.price}',
              onTap: () {
                _addItemToCart(item, variant: 'Full');
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 12),
            if (item.halfPrice != null && item.halfPrice! > 0)
              _variantTile(
                profile: profile,
                title: 'Half Portion',
                sub: item.halfUnit ?? 'Half Plate',
                price: '${profile.currencySymbol}${item.halfPrice}',
                onTap: () {
                  _addItemToCart(item, variant: 'Half');
                  Navigator.pop(context);
                },
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _variantTile({required ProfileProvider profile, required String title, required String sub, required String price, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        decoration: BoxDecoration(
          border: Border.all(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade200),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.w800, color: profile.textColor, fontSize: 14)),
                Text(sub, style: TextStyle(fontSize: 11, color: profile.secondaryTextColor)),
              ],
            ),
            Text(price, style: TextStyle(fontWeight: FontWeight.w900, color: profile.themeColor, fontSize: 16)),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate(ProfileProvider profile) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(primary: profile.themeColor),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemProvider = Provider.of<ItemProvider>(context);
    final catProvider = Provider.of<CategoryProvider>(context);
    final profileProvider = Provider.of<ProfileProvider>(context);
    final themeColor = profileProvider.themeColor;
    final isSale = _type == 'sale';
    final isPurchase = _type == 'purchase';

    final targetItemType = isSale ? 'selling' : 'purchase';
    final allCategories = catProvider.categories.map((e) => e.name).toList();
    
    // Show only categories that contain items of the target type
    List<String> displayedCategories = allCategories.where((cat) {
      return itemProvider.getItemsByCategory(cat).any((item) => item.itemType == targetItemType);
    }).toList();

    // Add virtual "All" categories
    if (isSale) {
      if (!displayedCategories.contains('All Sales')) {
        displayedCategories.insert(0, 'All Sales');
      }
    } else if (isPurchase) {
      if (!displayedCategories.contains('All Purchases')) {
        displayedCategories.insert(0, 'All Purchases');
      }
    } else {
      if (!displayedCategories.contains('All Expenses')) {
        displayedCategories.insert(0, 'All Expenses');
      }
    }

    if (!displayedCategories.contains(_selectedCategory) && displayedCategories.isNotEmpty) {
      _selectedCategory = displayedCategories.first;
    }

    // Filter Logic
    List<ItemModel> categoryItems;
    if (_searchQuery.isNotEmpty) {
      categoryItems = itemProvider.items.where((item) {
        return item.itemType == targetItemType && item.name.toLowerCase().contains(_searchQuery.toLowerCase());
      }).toList();
    } else {
      if (isSale && _selectedCategory == 'All Sales') {
        categoryItems = itemProvider.items.where((item) => item.itemType == 'selling').toList();
      } else if (isPurchase && _selectedCategory == 'All Purchases') {
        categoryItems = itemProvider.items.where((item) => item.itemType == 'purchase').toList();
      } else if (!isSale && !isPurchase && _selectedCategory == 'All Expenses') {
        categoryItems = itemProvider.items.where((item) => item.itemType == 'purchase').toList();
      } else {
        categoryItems = itemProvider.getItemsByCategory(_selectedCategory).where((item) {
          return item.itemType == targetItemType;
        }).toList();
      }
    }

    String screenTitle = isSale ? 'CREATE NEW SALE' : (isPurchase ? 'NEW PURCHASE' : 'RECORD EXPENSE');

    return Scaffold(
      backgroundColor: profileProvider.scaffoldColor,
      appBar: AppBar(
        backgroundColor: profileProvider.cardColor,
        foregroundColor: profileProvider.textColor,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
        title: Column(
          children: [
            Text(screenTitle, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
            GestureDetector(
              onTap: () => _pickDate(profileProvider),
              child: Text(
                DateFormat('dd MMM yyyy').format(_selectedDate),
                style: TextStyle(fontSize: 10, color: themeColor, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () => _pickDate(profileProvider),
            icon: Icon(Icons.calendar_month_rounded, color: themeColor, size: 20),
          ),
          IconButton(
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CategoryManagementScreen())),
            icon: const Icon(Icons.settings_suggest_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          // Category chips
          if (displayedCategories.isNotEmpty)
            Container(
              height: 55, 
              decoration: BoxDecoration(
                color: profileProvider.cardColor,
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
              ),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: displayedCategories.length,
                itemBuilder: (context, index) {
                  final cat = displayedCategories[index];
                  bool isSel = _selectedCategory == cat;
                  return GestureDetector(
                    onTap: () => setState(() => _selectedCategory = cat),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: isSel ? themeColor : (profileProvider.isDarkMode ? Colors.white.withOpacity(0.05) : Colors.grey.shade50),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isSel ? themeColor : (profileProvider.isDarkMode ? Colors.white10 : Colors.grey.shade100)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(_getCategoryIcon(cat), color: isSel ? Colors.white : profileProvider.secondaryTextColor, size: 14),
                          const SizedBox(width: 8),
                          Text(cat, style: TextStyle(
                            color: isSel ? Colors.white : profileProvider.secondaryTextColor,
                            fontWeight: isSel ? FontWeight.w900 : FontWeight.w600,
                            fontSize: 10,
                            letterSpacing: 0.5
                          )),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    style: TextStyle(color: profileProvider.textColor, fontWeight: FontWeight.bold),
                    decoration: InputDecoration(
                      hintText: 'Search items...',
                      hintStyle: TextStyle(color: profileProvider.secondaryTextColor.withOpacity(0.5)),
                      prefixIcon: Icon(Icons.search_rounded, color: themeColor),
                      filled: true,
                      fillColor: profileProvider.cardColor,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: profileProvider.isDarkMode ? const BorderSide(color: Colors.white10) : BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  Expanded(
                    child: categoryItems.isEmpty
                        ? Center(child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inventory_2_outlined, size: 48, color: profileProvider.secondaryTextColor.withOpacity(0.2)),
                              const SizedBox(height: 12),
                              Text('No items found', style: TextStyle(color: profileProvider.secondaryTextColor)),
                            ],
                          ))
                        : GridView.builder(
                            padding: const EdgeInsets.only(bottom: 120),
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 2, 
                              childAspectRatio: 1.45, 
                              crossAxisSpacing: 12, 
                              mainAxisSpacing: 12
                            ),
                            itemCount: categoryItems.length,
                            itemBuilder: (context, index) {
                              final item = categoryItems[index];
                              final cartItems = _cart.where((c) => c.item.id == item.id).toList();
                              double totalCount = cartItems.fold(0, (sum, c) => sum + c.quantity);
                              
                              return Container(
                                decoration: BoxDecoration(
                                  color: profileProvider.cardColor,
                                  borderRadius: BorderRadius.circular(20),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.06), 
                                      blurRadius: 10, 
                                      offset: const Offset(0, 4)
                                    )
                                  ],
                                  border: Border.all(color: totalCount > 0 ? themeColor.withOpacity(0.5) : (profileProvider.isDarkMode ? Colors.white10 : Colors.transparent)),
                                ),
                                child: Column(
                                  children: [
                                    Expanded(
                                      child: InkWell(
                                        onTap: () {
                                          if (item.halfPrice != null && item.halfPrice! > 0) {
                                            _showVariantPicker(item);
                                          } else {
                                            _addItemToCart(item);
                                          }
                                        },
                                        borderRadius: BorderRadius.circular(20),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          child: Column(
                                            mainAxisAlignment: MainAxisAlignment.center,
                                            children: [
                                              Text(item.name, 
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w900, 
                                                  fontSize: 12, 
                                                  color: profileProvider.textColor, 
                                                  height: 1.1,
                                                ),
                                                textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis),
                                              const SizedBox(height: 6),
                                              Text('${profileProvider.currencySymbol}${item.price}', 
                                                style: TextStyle(color: themeColor, fontWeight: FontWeight.w900, fontSize: 16)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                    if (totalCount > 0)
                                      Container(
                                        padding: const EdgeInsets.symmetric(vertical: 6),
                                        decoration: BoxDecoration(
                                          color: themeColor.withOpacity(0.08),
                                          borderRadius: const BorderRadius.vertical(bottom: Radius.circular(20)),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                          children: [
                                            _qtyActionBtn(profileProvider, Icons.remove_rounded, () => _removeItemFromCart(item)),
                                            Text('${totalCount.toInt()}', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, color: profileProvider.textColor)),
                                            _qtyActionBtn(profileProvider, Icons.add_rounded, () {
                                              if (item.halfPrice != null && item.halfPrice! > 0) {
                                                _showVariantPicker(item);
                                              } else {
                                                _addItemToCart(item);
                                              }
                                            }),
                                          ],
                                        ),
                                      )
                                    else
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                                        child: ElevatedButton(
                                          onPressed: () {
                                            if (item.halfPrice != null && item.halfPrice! > 0) {
                                              _showVariantPicker(item);
                                            } else {
                                              _addItemToCart(item);
                                            }
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: themeColor,
                                            foregroundColor: Colors.white,
                                            minimumSize: const Size(double.infinity, 32),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                            elevation: 0,
                                            padding: EdgeInsets.zero,
                                          ),
                                          child: const Text('ADD ITEM', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 0.5)),
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: _cart.isNotEmpty ? _buildFloatingCartButton(profileProvider) : null,
    );
  }

  Widget _qtyActionBtn(ProfileProvider profile, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: profile.cardColor, shape: BoxShape.circle, boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4)]),
        child: Icon(icon, size: 16, color: profile.textColor),
      ),
    );
  }

  Widget _buildFloatingCartButton(ProfileProvider profile) {
    final themeColor = profile.themeColor;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(20),
      child: FloatingActionButton.extended(
        onPressed: () async {
          await Navigator.push(
            context, 
            MaterialPageRoute(builder: (context) => CartDetailsScreen(
              cart: _cart, 
              type: _type, 
              selectedCategory: _selectedCategory, 
              selectedDate: _selectedDate,
              existingTransaction: widget.transaction,
            ))
          );
          setState(() {});
        },
        backgroundColor: themeColor,
        elevation: 10,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        label: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(10)),
              child: Text('${_cart.length} ITEMS', style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 12)),
            ),
            const SizedBox(width: 20),
            const Text('REVIEW & SAVE ENTRY', style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 1)),
            const SizedBox(width: 16),
            const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.white),
          ],
        ),
      ),
    );
  }

  IconData _getCategoryIcon(String category) {
    String cat = category.toLowerCase();
    if (cat.contains('all')) return Icons.grid_view_rounded;
    if (cat.contains('sale')) return Icons.auto_graph_rounded;
    if (cat.contains('purchase')) return Icons.shopping_bag_rounded;
    if (cat.contains('veg')) return Icons.eco_rounded;
    if (cat.contains('raw')) return Icons.inventory_2_rounded;
    return Icons.category_rounded;
  }
}
