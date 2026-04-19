import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../models/category_model.dart';
import '../../models/transaction_model.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/item_provider.dart';
import '../../providers/profile_provider.dart';
import '../../models/cart_item.dart';
import '../../models/item_model.dart';
import '../../services/print_service.dart';

class CartDetailsScreen extends StatefulWidget {
  final List<CartItem> cart;
  final String type;
  final String selectedCategory;
  final DateTime selectedDate;
  final TransactionModel? existingTransaction;

  const CartDetailsScreen({
    super.key,
    required this.cart,
    required this.type,
    required this.selectedCategory,
    required this.selectedDate,
    this.existingTransaction,
  });

  @override
  State<CartDetailsScreen> createState() => _CartDetailsScreenState();
}

class _CartDetailsScreenState extends State<CartDetailsScreen> {
  final TextEditingController _paidAmountController = TextEditingController();
  final TextEditingController _discountController = TextEditingController(
    text: '0',
  );
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _cashSplitController = TextEditingController();
  final TextEditingController _upiSplitController = TextEditingController();
  final TextEditingController _vendorNameController = TextEditingController();

  String _paymentMode = 'Cash';
  bool _isLoading = false;
  String _globalServingMethod = 'Dine-in';
  String _selectedTable = '1';
  String _selectedCountryCode = '+91';

  final List<Map<String, String>> _countryCodes = [
    {'code': '+91', 'name': 'IN'},
    {'code': '+1', 'name': 'US'},
    {'code': '+44', 'name': 'UK'},
    {'code': '+971', 'name': 'AE'},
    {'code': '+92', 'name': 'PK'},
    {'code': '+880', 'name': 'BD'},
    {'code': '+977', 'name': 'NP'},
    {'code': '+61', 'name': 'AU'},
    {'code': '+1', 'name': 'CA'},
    {'code': '+966', 'name': 'SA'},
    {'code': '+974', 'name': 'QA'},
    {'code': '+965', 'name': 'KW'},
    {'code': '+968', 'name': 'OM'},
    {'code': '+65', 'name': 'SG'},
    {'code': '+60', 'name': 'MY'},
    {'code': '+62', 'name': 'ID'},
    {'code': '+49', 'name': 'DE'},
    {'code': '+33', 'name': 'FR'},
    {'code': '+39', 'name': 'IT'},
    {'code': '+34', 'name': 'ES'},
    {'code': '+7', 'name': 'RU'},
    {'code': '+81', 'name': 'JP'},
    {'code': '+86', 'name': 'CN'},
    {'code': '+27', 'name': 'ZA'},
    {'code': '+234', 'name': 'NG'},
    {'code': '+55', 'name': 'BR'},
    {'code': '+52', 'name': 'MX'},
  ];

  bool get _isSellingType =>
      widget.type.toLowerCase() == 'sale' ||
      widget.type.toLowerCase() == 'income';

  @override
  void initState() {
    super.initState();
    final profile = Provider.of<ProfileProvider>(context, listen: false);

    if (widget.existingTransaction != null) {
      _paymentMode = widget.existingTransaction!.paymentMode;
      String contact = widget.existingTransaction!.customerContact;
      if (contact.startsWith('+')) {
        for (var c in _countryCodes) {
          if (contact.startsWith(c['code']!)) {
            _selectedCountryCode = c['code']!;
            _contactController.text = contact.substring(c['code']!.length);
            break;
          }
        }
        if (_contactController.text.isEmpty) _contactController.text = contact;
      } else {
        _contactController.text = contact;
      }

      _discountController.text = widget.existingTransaction!.discountValue
          .toStringAsFixed(0);
      _paidAmountController.text = widget.existingTransaction!.paidAmount
          .toStringAsFixed(0);
      _cashSplitController.text = widget.existingTransaction!.cashAmount
          .toStringAsFixed(0);
      _upiSplitController.text = widget.existingTransaction!.upiAmount
          .toStringAsFixed(0);
      _vendorNameController.text =
          widget.existingTransaction!.description.contains(' | Vendor: ')
          ? widget.existingTransaction!.description
                .split(' | Vendor: ')
                .last
                .split(' | ')
                .first
          : '';

      final items = widget.existingTransaction!.parsedItems;
      if (items.isNotEmpty) {
        _globalServingMethod = items.first['serving_method'] ?? 'Dine-in';
        _selectedTable =
            items.first['table_number'] ?? (profile.totalTables > 0 ? '1' : '');
      }
      _populateCartFromTransaction();
    } else if (widget.cart.isNotEmpty) {
      _globalServingMethod = widget.cart.first.servingMethod;
      _selectedTable =
          widget.cart.first.tableNumber.isEmpty && profile.totalTables > 0
          ? '1'
          : widget.cart.first.tableNumber;
    } else {
      _selectedTable = profile.totalTables > 0 ? '1' : '';
    }
    _syncPaidAmount();
  }

  @override
  void dispose() {
    _paidAmountController.dispose();
    _discountController.dispose();
    _contactController.dispose();
    _cashSplitController.dispose();
    _upiSplitController.dispose();
    _vendorNameController.dispose();
    super.dispose();
  }

  // Calculated properties for real-time UI refresh
  double get _currentSubtotal {
    double subtotal = 0;
    for (var cartItem in widget.cart) {
      subtotal += _getItemTotalPrice(cartItem);
    }
    return subtotal;
  }

  double get _currentGrandTotal {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    double sub = _currentSubtotal;
    double tax = sub * (profile.taxPercentage / 100);
    double disc = double.tryParse(_discountController.text) ?? 0;
    double total = sub + tax - disc;
    return total < 0 ? 0 : total;
  }

  void _syncPaidAmount() {
    setState(() {
      double total = _currentGrandTotal;
      if (_paymentMode != 'Credit' && _paymentMode != 'Split') {
        _paidAmountController.text = total.toStringAsFixed(0);
      }
      if (_paymentMode == 'Split') {
        double cash = double.tryParse(_cashSplitController.text) ?? total;
        if (cash > total) cash = total;
        _cashSplitController.text = cash.toStringAsFixed(0);
        _upiSplitController.text = (total - cash).toStringAsFixed(0);
      }
    });
  }

  void _populateCartFromTransaction() {
    if (widget.existingTransaction == null || widget.cart.isNotEmpty) return;

    final itemProvider = Provider.of<ItemProvider>(context, listen: false);
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    for (var itemMap in widget.existingTransaction!.parsedItems) {
      final name = itemMap['name'] ?? '';
      final qty = double.tryParse(itemMap['qty'].toString()) ?? 1.0;
      final price = double.tryParse(itemMap['price'].toString()) ?? 0.0;
      final variant = itemMap['variant'] ?? 'Full';
      final unit = itemMap['unit'] ?? (variant == 'Half' ? 'Half' : 'Full');
      final servingMethod = itemMap['serving_method'] ?? 'Dine-in';
      final tableNumber =
          itemMap['table_number'] ?? (profile.totalTables > 0 ? '1' : '');
      final extraQty = double.tryParse(itemMap['extra_qty'].toString()) ?? 0.0;
      final extraPrice =
          double.tryParse(itemMap['extra_price'].toString()) ?? 0.0;

      final item = itemProvider.items.firstWhere(
        (i) => i.name == name,
        orElse: () => ItemModel(
          name: name,
          category: itemMap['category'] ?? 'General',
          unit: unit,
          minStock: 0,
          currentStock: 0,
          price: price,
          halfPrice: double.tryParse(itemMap['half_price'].toString()),
          itemType: 'selling',
        ),
      );

      widget.cart.add(
        CartItem(
          item: item,
          quantity: qty,
          price: price,
          variant: variant,
          unit: unit,
          extraPieces: extraQty,
          extraPrice: extraPrice,
          servingMethod: servingMethod,
          tableNumber: tableNumber,
        ),
      );
    }
  }

  double _getItemTotalPrice(CartItem c) {
    double base;
    final double fullP = c.item.price ?? 0;
    final double hPrice = (c.item.halfPrice != null && c.item.halfPrice! > 0)
        ? c.item.halfPrice!
        : fullP;

    // Rule: Full plates at full price + remainder charges ONE half plate at fixed half price
    if (_isSellingType && hPrice > 0 && hPrice < fullP) {
      int fullPlates = c.quantity.floor();
      double remainder = c.quantity - fullPlates;
      // For remainder > 0, charge exactly ONE half plate (not proportional to remainder)
      base = (fullPlates * fullP) + (remainder > 0 ? hPrice : 0);
    } else {
      base = c.quantity * c.price;
    }

    // Logic Fix: Extras multiplication
    double totalExtra = c.extraPieces * c.extraPrice;

    return base + totalExtra;
  }

  void _showManualQuantityDialog(CartItem cartItem) {
    final itemProvider = Provider.of<ItemProvider>(context, listen: false);
    final cat = itemProvider.categories.firstWhere(
      (c) => c.name == cartItem.item.category,
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
    final controller = TextEditingController(
      text: cartItem.quantity.toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: profile.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Enter Quantity',
          style: TextStyle(
            color: profile.textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Quantity'),
          style: TextStyle(
            color: profile.textColor,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () {
              final newQty = double.tryParse(controller.text) ?? 0;
              setState(() {
                if (newQty > 0) {
                  cartItem.quantity = newQty;
                } else {
                  widget.cart.remove(cartItem);
                }
                _syncPaidAmount();
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: profile.themeColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('UPDATE'),
          ),
        ],
      ),
    );
  }

  void _setGlobalServingMethod(String method) {
    setState(() {
      _globalServingMethod = method;
      for (var item in widget.cart) {
        item.servingMethod = method;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final profileProvider = Provider.of<ProfileProvider>(context);
    final themeColor = profileProvider.themeColor;
    final isSale = _isSellingType;
    final isPurchase = widget.type == 'purchase';

    return Scaffold(
      backgroundColor: profileProvider.scaffoldColor,
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        backgroundColor: profileProvider.cardColor,
        foregroundColor: profileProvider.textColor,
        elevation: 0,
        centerTitle: true,
        title: Text(
          widget.existingTransaction == null ? 'FINAL REVIEW' : 'EDIT BILL',
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSummaryCard(profileProvider),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'ORDER ITEMS',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                          color: profileProvider.secondaryTextColor,
                          letterSpacing: 0.5,
                        ),
                      ),
                      Text(
                        '${widget.cart.length} Items',
                        style: TextStyle(
                          color: themeColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildItemsList(profileProvider),
                  const SizedBox(height: 2),
                  Text(
                    'FINANCIAL DETAILS',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: profileProvider.secondaryTextColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),

                  _entryField(
                    _discountController,
                    'Add Discount (₹)',
                    Icons.local_offer_rounded,
                    themeColor,
                    profileProvider,
                    onChanged: (_) => _syncPaidAmount(),
                  ),
                  const SizedBox(height: 24),

                  Text(
                    'PAYMENT METHOD',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: profileProvider.secondaryTextColor,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildPaymentMethodSelector(themeColor, profileProvider),
                  const SizedBox(height: 16),
                  if (_paymentMode == 'Split') ...[
                    Row(
                      children: [
                        Expanded(
                          child: _entryField(
                            _cashSplitController,
                            'Cash Paid',
                            Icons.money_rounded,
                            Colors.green,
                            profileProvider,
                            onChanged: (val) {
                              double total = _currentGrandTotal;
                              double cash = double.tryParse(val) ?? 0;
                              if (cash > total) cash = total;
                              setState(() {
                                _upiSplitController.text = (total - cash)
                                    .toStringAsFixed(0);
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: _upiSplitField(profileProvider)),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_paymentMode == 'Credit' ||
                      _paymentMode == 'UPI' ||
                      _paymentMode == 'Split')
                    Column(
                      children: [
                        if (isPurchase)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _entryField(
                              _vendorNameController,
                              'Shop / Vendor Name',
                              Icons.store_rounded,
                              themeColor,
                              profileProvider,
                            ),
                          ),
                        _contactFieldWithCode(profileProvider, isPurchase),
                      ],
                    ),
                  if (_paymentMode == 'Credit')
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: _entryField(
                        _paidAmountController,
                        'Paid Amount (Deposit)',
                        Icons.account_balance_wallet_rounded,
                        themeColor,
                        profileProvider,
                      ),
                    ),
                ],
              ),
            ),
          ),
          _buildBottomActionArea(profileProvider, isSale, isPurchase),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(ProfileProvider profile) {
    double sub = _currentSubtotal;
    double tax = sub * (profile.taxPercentage / 100);
    double disc = double.tryParse(_discountController.text) ?? 0;
    double total = _currentGrandTotal;
    double paid = 0;

    if (_paymentMode == 'Credit') {
      paid = double.tryParse(_paidAmountController.text) ?? 0;
    } else if (_paymentMode == 'Split') {
      paid =
          (double.tryParse(_cashSplitController.text) ?? 0) +
          (double.tryParse(_upiSplitController.text) ?? 0);
    } else {
      paid = total;
    }

    double balance = total - paid;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            profile.themeColor,
            profile.themeColor.withValues(alpha: 0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: profile.themeShadow,
      ),
      child: Column(
        children: [
          _summaryRow(
            'Subtotal',
            '${profile.currencySymbol}${sub.toStringAsFixed(0)}',
            Colors.white.withValues(alpha: 0.9),
          ),
          if (profile.taxPercentage > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: _summaryRow(
                'Tax (${profile.taxPercentage}%)',
                '${profile.currencySymbol}${tax.toStringAsFixed(0)}',
                Colors.white.withValues(alpha: 0.9),
              ),
            ),
          const SizedBox(height: 8),
          if (disc > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: _summaryRow(
                'Discount',
                '- ${profile.currencySymbol}${disc.toStringAsFixed(0)}',
                Colors.white.withValues(alpha: 0.9),
              ),
            ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(color: Colors.white24, height: 1),
          ),
          _summaryRow(
            'Grand Total',
            '${profile.currencySymbol}${total.toStringAsFixed(0)}',
            Colors.white,
            isBold: true,
          ),

          if (_paymentMode == 'Credit') ...[
            const SizedBox(height: 12),
            _summaryRow(
              'Paid (Deposit)',
              '${profile.currencySymbol}${paid.toStringAsFixed(0)}',
              Colors.greenAccent.withValues(alpha: 0.9),
              isBold: false,
            ),
            _summaryRow(
              'Remaining',
              '${profile.currencySymbol}${balance.toStringAsFixed(0)}',
              Colors.redAccent.shade100,
              isBold: true,
            ),
          ],

          if (_paymentMode == 'Split') ...[
            const SizedBox(height: 12),
            _summaryRow(
              'Cash Part',
              '${profile.currencySymbol}${(double.tryParse(_cashSplitController.text) ?? 0).toStringAsFixed(0)}',
              Colors.white.withValues(alpha: 0.9),
            ),
            _summaryRow(
              'UPI Part',
              '${profile.currencySymbol}${(double.tryParse(_upiSplitController.text) ?? 0).toStringAsFixed(0)}',
              Colors.white.withValues(alpha: 0.9),
            ),
          ],
        ],
      ),
    );
  }

  Widget _summaryRow(
    String label,
    String value,
    Color color, {
    bool isBold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: isBold ? 24 : 16,
            fontWeight: isBold ? FontWeight.w900 : FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildItemsList(ProfileProvider profile) {
    final themeColor = profile.themeColor;
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.cart.length,
      itemBuilder: (context, index) {
        final c = widget.cart[index];
        final bool isHalf =
            c.quantity == 0.5 && c.variant.toLowerCase() == 'half';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: profile.cardColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade100,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    height: 48,
                    width: 48,
                    decoration: BoxDecoration(
                      color: themeColor.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: themeColor.withValues(alpha: 0.1),
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    alignment: Alignment.center,
                    child: _buildItemIcon(c.item),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          c.item.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                            color: profile.textColor,
                          ),
                        ),
                        Text(
                          '${isHalf ? 'Half' : c.variant} • ${c.item.category}',
                          style: TextStyle(
                            fontSize: 10,
                            color: profile.secondaryTextColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _qtyBtn(
                    Icons.remove_rounded,
                    profile,
                    () => setState(() {
                      double step = c.variant.toLowerCase() == 'half'
                          ? 0.5
                          : 1.0;
                      if (c.quantity > step) {
                        c.quantity -= step;
                      } else {
                        widget.cart.removeAt(index);
                      }
                      _syncPaidAmount();
                    }),
                  ),
                  GestureDetector(
                    onTap: () => _showManualQuantityDialog(c),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      child: Column(
                        children: [
                          Text(
                            isHalf
                                ? 'Half'
                                : '${c.quantity % 1 == 0 ? c.quantity.toInt() : c.quantity}',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: profile.textColor,
                              fontSize: 15,
                            ),
                          ),
                          Text(
                            c.unit,
                            style: TextStyle(
                              fontSize: 9,
                              color: profile.secondaryTextColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _qtyBtn(
                    Icons.add_rounded,
                    profile,
                    () => setState(() {
                      double step = c.variant.toLowerCase() == 'half'
                          ? 0.5
                          : 1.0;
                      c.quantity += step;
                      _syncPaidAmount();
                    }),
                  ),
                ],
              ),
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Divider(height: 1, thickness: 0.5),
              ),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: _smallEntryField('Price', profile, (val) {
                      setState(() {
                        c.price = double.tryParse(val) ?? c.price;
                        _syncPaidAmount();
                      });
                    }, initial: c.price.toStringAsFixed(0)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _smallEntryField(
                      'Ex Qty',
                      profile,
                      (val) {
                        setState(() {
                          c.extraPieces = double.tryParse(val) ?? 0;
                          _syncPaidAmount();
                        });
                      },
                      initial: c.extraPieces > 0
                          ? c.extraPieces.toInt().toString()
                          : '',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _smallEntryField(
                      'Ex Rs',
                      profile,
                      (val) {
                        setState(() {
                          c.extraPrice = double.tryParse(val) ?? 0;
                          _syncPaidAmount();
                        });
                      },
                      initial: c.extraPrice > 0
                          ? c.extraPrice.toInt().toString()
                          : '',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${profile.currencySymbol}${_getItemTotalPrice(c).toStringAsFixed(0)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: themeColor,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
              if (_isSellingType) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    _servingCheckbox(c, 'Dine-in', profile),
                    const SizedBox(width: 16),
                    _servingCheckbox(c, 'Takeaway', profile),
                    const Spacer(),
                    if (c.servingMethod == 'Dine-in' && profile.totalTables > 0)
                      Text(
                        'Table: ${c.tableNumber.isEmpty ? _selectedTable : c.tableNumber}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: themeColor.withValues(alpha: 0.7),
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _qtyBtn(IconData icon, ProfileProvider profile, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 32,
        width: 32,
        decoration: BoxDecoration(
          color: profile.themeColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: profile.themeColor),
      ),
    );
  }

  Widget _buildItemIcon(ItemModel item) {
    if (item.icon != null && item.icon!.isNotEmpty) {
      if (item.icon!.startsWith('/') || item.icon!.contains('com.example')) {
        return Image.file(
          File(item.icon!),
          fit: BoxFit.cover,
          width: 48,
          height: 48,
          errorBuilder: (context, error, stackTrace) =>
              const Text('🍽️', style: TextStyle(fontSize: 24)),
        );
      }
      return Text(item.icon!, style: const TextStyle(fontSize: 24));
    }
    return const Text('🍽️', style: TextStyle(fontSize: 24));
  }

  Widget _smallEntryField(
    String hint,
    ProfileProvider profile,
    Function(String) onChange, {
    String? initial,
  }) {
    return SizedBox(
      height: 38,
      child: TextFormField(
        initialValue: initial,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        onChanged: onChange,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w900,
          color: profile.textColor,
        ),
        decoration: InputDecoration(
          labelText: hint,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          labelStyle: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            color: profile.secondaryTextColor,
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 0,
          ),
          filled: true,
          fillColor: profile.scaffoldColor,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: profile.themeColor.withValues(alpha: 0.5),
            ),
          ),
        ),
      ),
    );
  }

  Widget _servingCheckbox(
    CartItem item,
    String method,
    ProfileProvider profile,
  ) {
    bool isSelected = item.servingMethod == method;
    return InkWell(
      onTap: () {
        setState(() => item.servingMethod = method);
        _syncPaidAmount();
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? profile.themeColor
                      : profile.secondaryTextColor.withValues(alpha: 0.5),
                  width: 2,
                ),
                color: isSelected ? profile.themeColor : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 10, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 8),
            Text(
              method,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                color: isSelected
                    ? profile.themeColor
                    : profile.secondaryTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentMethodSelector(
    Color themeColor,
    ProfileProvider profile,
  ) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: profile.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade100,
        ),
      ),
      child: Row(
        children: ['Cash', 'UPI', 'Split', 'Credit'].map((mode) {
          bool isSelected = _paymentMode == mode;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _paymentMode = mode;
                _syncPaidAmount();
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? themeColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  mode,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : profile.secondaryTextColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBottomActionArea(
    ProfileProvider profile,
    bool isSale,
    bool isPurchase,
  ) {
    bool canShowPending =
        isSale &&
        (widget.existingTransaction == null ||
            widget.existingTransaction?.status == 'pending');

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      decoration: BoxDecoration(
        color: profile.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isSale) ...[
              _buildGlobalServingAndTableSelector(profile),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                if (canShowPending) ...[
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isLoading
                          ? null
                          : () => _handleSave(isPending: true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey.shade100,
                        foregroundColor: Colors.blueGrey.shade800,
                        minimumSize: const Size(double.infinity, 54),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        widget.existingTransaction != null
                            ? 'UPDATE PENDING'
                            : 'PENDING',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : () => _handleSave(isPending: false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSale
                          ? Colors.green.shade600
                          : (isPurchase
                                ? Colors.orange.shade700
                                : Colors.red.shade600),
                      minimumSize: const Size(double.infinity, 54),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                      shadowColor: (isSale ? Colors.green : Colors.orange)
                          .withValues(alpha: 0.3),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 3,
                            ),
                          )
                        : Text(
                            widget.existingTransaction?.status == 'pending'
                                ? 'COMPLETE BILL'
                                : 'CONFIRM BILL',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                              color: Colors.white,
                              letterSpacing: 1,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlobalServingAndTableSelector(ProfileProvider profile) {
    return Row(
      children: [
        Expanded(
          flex: 2,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: profile.scaffoldColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: profile.isDarkMode
                    ? Colors.white10
                    : Colors.grey.shade200,
              ),
            ),
            child: Row(
              children: ['Dine-in', 'Takeaway'].map((method) {
                bool isSelected = _globalServingMethod == method;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => _setGlobalServingMethod(method),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? profile.themeColor
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        method,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: isSelected
                              ? Colors.white
                              : profile.secondaryTextColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        if (profile.totalTables > 0) ...[
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              decoration: BoxDecoration(
                color: profile.scaffoldColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: profile.isDarkMode
                      ? Colors.white10
                      : Colors.grey.shade200,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedTable.isEmpty && profile.totalTables > 0
                      ? '1'
                      : _selectedTable,
                  isExpanded: true,
                  icon: Icon(
                    Icons.keyboard_arrow_down,
                    size: 18,
                    color: profile.themeColor,
                  ),
                  style: TextStyle(
                    color: profile.textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  dropdownColor: profile.cardColor,
                  items:
                      List.generate(
                            profile.totalTables,
                            (i) => (i + 1).toString(),
                          )
                          .map(
                            (t) =>
                                DropdownMenuItem(value: t, child: Text('T-$t')),
                          )
                          .toList(),
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedTable = val);
                  },
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _pickContact() async {
    if (await Permission.contacts.request().isGranted) {
      final contact = await FlutterContacts.openExternalPick();
      if (contact != null) {
        // Re-fetch the full contact details because openExternalPick returns limited info
        final fullContact = await FlutterContacts.getContact(contact.id);
        if (fullContact != null && fullContact.phones.isNotEmpty) {
          String phone = fullContact.phones.first.number.replaceAll(
            RegExp(r'\s+|-|\(|\)'),
            '',
          );

          // Handle if phone already contains country code
          bool foundCode = false;
          for (var c in _countryCodes) {
            if (phone.startsWith(c['code']!)) {
              setState(() {
                _selectedCountryCode = c['code']!;
                _contactController.text = phone.substring(c['code']!.length);
              });
              foundCode = true;
              break;
            }
          }

          if (!foundCode) {
            setState(() {
              _contactController.text = phone;
            });
          }
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Contacts permission is required to pick a contact'),
          ),
        );
      }
    }
  }

  Widget _contactFieldWithCode(ProfileProvider profile, bool isPurchase) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: profile.scaffoldColor,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: profile.isDarkMode
                      ? Colors.white10
                      : Colors.grey.shade200,
                ),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedCountryCode,
                  icon: const Icon(Icons.arrow_drop_down, size: 20),
                  dropdownColor: profile.cardColor,
                  style: TextStyle(
                    color: profile.textColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  items: _countryCodes
                      .map(
                        (c) => DropdownMenuItem(
                          value: c['code'],
                          child: Text('${c['name']} ${c['code']}'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedCountryCode = v);
                  },
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextFormField(
                controller: _contactController,
                keyboardType: TextInputType.phone,
                style: TextStyle(
                  color: profile.textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                decoration: InputDecoration(
                  labelText: isPurchase ? 'Supplier Mobile' : 'Customer Mobile',
                  prefixIcon: Icon(
                    Icons.phone_android_rounded,
                    size: 20,
                    color: profile.themeColor,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      Icons.contact_page_rounded,
                      color: profile.themeColor,
                    ),
                    onPressed: _pickContact,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _upiSplitField(ProfileProvider profileProvider) {
    return _entryField(
      _upiSplitController,
      'UPI Paid',
      Icons.qr_code_rounded,
      Colors.blue,
      profileProvider,
      onChanged: (val) {
        double total = _currentGrandTotal;
        double upi = double.tryParse(val) ?? 0;
        if (upi > total) upi = total;
        setState(() {
          _cashSplitController.text = (total - upi).toStringAsFixed(0);
        });
      },
    );
  }

  Widget _entryField(
    TextEditingController controller,
    String label,
    IconData icon,
    Color themeColor,
    ProfileProvider profile, {
    Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.name,
      onChanged: (val) {
        setState(() {}); // Trigger rebuild to update Summary Card in real-time
        if (onChanged != null) onChanged(val);
      },
      onTap: () {
        if (controller.text == '0' || controller.text == '0.0') {
          controller.clear();
        }
      },
      style: TextStyle(
        color: profile.textColor,
        fontWeight: FontWeight.bold,
        fontSize: 14,
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: themeColor),
      ),
    );
  }

  Future<void> _handleSave({bool isPending = false}) async {
    final totalAmt = _currentGrandTotal;
    if (totalAmt < 0) return;

    setState(() => _isLoading = true);
    try {
      final txProvider = Provider.of<TransactionProvider>(
        context,
        listen: false,
      );
      final itemProvider = Provider.of<ItemProvider>(context, listen: false);
      final profile = Provider.of<ProfileProvider>(context, listen: false);

      String description = jsonEncode(
        widget.cart
            .map(
              (e) => {
                'id': e.item.id,
                'name': e.item.name,
                'category': e.item.category,
                'qty': e.quantity,
                'unit': e.unit,
                'variant': e.variant,
                'price': e.price,
                'purchase_price': e.item.purchasePrice ?? 0,
                'transport_cost': e.item.transportCost ?? 0,
                'full_price': e.item.price ?? 0,
                'half_price': e.item.halfPrice ?? 0,
                'extra_qty': e.extraPieces,
                'extra_price': e.extraPrice,
                'serving_method': e.servingMethod,
                'table_number': _selectedTable,
                'item_type': e.item.itemType,
              },
            )
            .toList(),
      );

      double sub = _currentSubtotal;
      double taxAmt = sub * (profile.taxPercentage / 100);
      double discAmt = double.tryParse(_discountController.text) ?? 0;

      description +=
          " | Subtotal: ₹$sub | Tax: ₹${taxAmt.toStringAsFixed(0)} | Discount: ₹${discAmt.toStringAsFixed(0)}";

      if (widget.type.toLowerCase() == 'purchase' &&
          _vendorNameController.text.isNotEmpty) {
        description += " | Vendor: ${_vendorNameController.text.trim()}";
      }

      double paidAmt = totalAmt;
      if (_paymentMode == 'Credit') {
        paidAmt = double.tryParse(_paidAmountController.text) ?? 0;
      }

      final txData = TransactionModel(
        id: widget.existingTransaction?.id,
        type: widget.existingTransaction?.type ?? widget.type,
        category: widget.selectedCategory,
        amount: totalAmt,
        paidAmount: paidAmt,
        description: description,
        paymentMode: _paymentMode,
        date: widget.selectedDate,
        customerContact: _contactController.text.trim().isEmpty
            ? ''
            : (_contactController.text.trim().startsWith('+')
                  ? _contactController.text.trim()
                  : '$_selectedCountryCode${_contactController.text.trim()}'),
        cashAmount: _paymentMode == 'Split'
            ? (double.tryParse(_cashSplitController.text) ?? 0)
            : (_paymentMode == 'Cash' ? totalAmt : 0),
        upiAmount: _paymentMode == 'Split'
            ? (double.tryParse(_upiSplitController.text) ?? 0)
            : (_paymentMode == 'UPI' ? totalAmt : 0),
        status: isPending ? 'pending' : 'completed',
      );

      TransactionModel? savedTx;
      if (widget.existingTransaction == null) {
        savedTx = await txProvider.addTransaction(txData, itemProvider);
      } else {
        savedTx = await txProvider.updateTransaction(
          txData,
          itemProvider,
          oldTx: widget.existingTransaction,
        );
      }

      if (profile.isAutoPrintEnabled && savedTx != null && mounted) {
        await PrintService().printSmart(context, savedTx);
      }

      if (mounted) {
        if (isPending) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        } else {
          Navigator.pop(context, true);
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
