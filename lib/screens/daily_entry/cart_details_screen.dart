import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/transaction_model.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/item_provider.dart';
import '../../providers/profile_provider.dart';
import '../../models/cart_item.dart';
import '../../services/notification_service.dart';

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
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _paidAmountController = TextEditingController();
  final TextEditingController _discountController = TextEditingController(text: '0');
  final TextEditingController _contactController = TextEditingController();
  final TextEditingController _cashSplitController = TextEditingController();
  final TextEditingController _upiSplitController = TextEditingController();

  String _paymentMode = 'Cash';
  bool _isLoading = false;
  String _globalServingMethod = 'Dine-in';
  String _selectedTable = '1';

  @override
  void initState() {
    super.initState();
    if (widget.existingTransaction != null) {
      _paymentMode = widget.existingTransaction!.paymentMode;
      _contactController.text = widget.existingTransaction!.customerContact;
      _discountController.text = widget.existingTransaction!.discountValue.toStringAsFixed(0);
      _paidAmountController.text = widget.existingTransaction!.paidAmount.toStringAsFixed(0);
      _cashSplitController.text = widget.existingTransaction!.cashAmount.toStringAsFixed(0);
      _upiSplitController.text = widget.existingTransaction!.upiAmount.toStringAsFixed(0);

      final items = widget.existingTransaction!.parsedItems;
      if (items.isNotEmpty) {
        _globalServingMethod = items.first['serving_method'] ?? 'Dine-in';
        _selectedTable = items.first['table_number'] ?? '1';
      }
    } else if (widget.cart.isNotEmpty) {
      _globalServingMethod = widget.cart.first.servingMethod;
      _selectedTable = widget.cart.first.tableNumber;
    }
    _calculateTotal();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _paidAmountController.dispose();
    _discountController.dispose();
    _contactController.dispose();
    _cashSplitController.dispose();
    _upiSplitController.dispose();
    super.dispose();
  }

  void _calculateTotal() {
    double subtotal = 0;
    for (var item in widget.cart) {
      subtotal += (item.price * item.quantity) + item.extraPrice;
    }

    final profile = Provider.of<ProfileProvider>(context, listen: false);
    double taxAmount = subtotal * (profile.taxPercentage / 100);
    double discount = double.tryParse(_discountController.text) ?? 0;
    double grandTotal = subtotal + taxAmount - discount;
    if (grandTotal < 0) grandTotal = 0;

    _amountController.text = grandTotal.toStringAsFixed(0);

    if (_paymentMode != 'Credit' && _paymentMode != 'Split') {
      _paidAmountController.text = grandTotal.toStringAsFixed(0);
    }

    if (_paymentMode == 'Split' && _cashSplitController.text.isEmpty && _upiSplitController.text.isEmpty) {
      _cashSplitController.text = grandTotal.toStringAsFixed(0);
      _upiSplitController.text = '0';
    }
  }

  void _showManualQuantityDialog(CartItem cartItem) {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final controller = TextEditingController(text: cartItem.quantity.toInt().toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: profile.cardColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text('Enter Quantity', style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Quantity'),
          style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          ElevatedButton(
            onPressed: () {
              final newQty = double.tryParse(controller.text) ?? 0;
              setState(() {
                if (newQty > 0) {
                  cartItem.quantity = newQty;
                } else {
                  widget.cart.remove(cartItem);
                }
                _calculateTotal();
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: profile.themeColor, foregroundColor: Colors.white),
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
    final isSale = widget.type == 'sale';
    final isPurchase = widget.type == 'purchase';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, dynamic result) async {
        if (didPop) return;
        Navigator.pop(context, widget.cart.isEmpty);
      },
      child: Theme(
        data: Theme.of(context).copyWith(
          bottomSheetTheme: const BottomSheetThemeData(
            backgroundColor: Colors.transparent,
            elevation: 0,
          ),
        ),
        child: Scaffold(
          backgroundColor: profileProvider.scaffoldColor,
          appBar: AppBar(
            backgroundColor: profileProvider.cardColor,
            foregroundColor: profileProvider.textColor,
            elevation: 0,
            centerTitle: true,
            title: Text(widget.existingTransaction == null ? 'FINAL REVIEW' : 'EDIT BILL',
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
          ),
          body: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      _buildSummaryCard(profileProvider),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('ORDER ITEMS', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: profileProvider.secondaryTextColor, letterSpacing: 0.5)),
                          Text('${widget.cart.length} Items', style: TextStyle(color: themeColor, fontWeight: FontWeight.bold, fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildItemsList(profileProvider),
                      const SizedBox(height: 2),
                      Text('PAYMENT DETAILS', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: profileProvider.secondaryTextColor, letterSpacing: 0.5)),
                      const SizedBox(height: 12),
                      _buildPaymentMethodSelector(themeColor, profileProvider),
                      const SizedBox(height: 16),
                      if (_paymentMode == 'Split') ...[
                        Row(
                          children: [
                            Expanded(
                              child: _entryField(_cashSplitController, 'Cash Paid', Icons.money_rounded, Colors.green, profileProvider, onChanged: (val) {
                                double total = double.tryParse(_amountController.text) ?? 0;
                                double cash = double.tryParse(val) ?? 0;
                                if (cash > total) cash = total;
                                _upiSplitController.text = (total - cash).toStringAsFixed(0);
                              }),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _upiSplitField(profileProvider),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (_paymentMode == 'Credit' || _paymentMode == 'UPI' || _paymentMode == 'Split')
                        _entryField(_contactController, isPurchase ? 'Supplier Mobile' : 'Customer Mobile', Icons.phone_android_rounded, themeColor, profileProvider, type: TextInputType.phone),
                      if (_paymentMode == 'Credit')
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: _entryField(_paidAmountController, 'Paid Amount (Deposit)', Icons.account_balance_wallet_rounded, themeColor, profileProvider),
                        ),
                      const SizedBox(height: 8),
                      _entryField(_discountController, 'Add Discount (₹)', Icons.local_offer_rounded, themeColor, profileProvider, onChanged: (_) => _calculateTotal()),
                      const SizedBox(height: 180),
                    ],
                  ),
                ),
              ),
            ],
          ),
          bottomSheet: _buildBottomActionArea(profileProvider, isSale, isPurchase),
        ),
      ),
    );
  }

  Widget _buildSummaryCard(ProfileProvider profile) {
    double subtotal = 0;
    for (var item in widget.cart) {
      subtotal += (item.price * item.quantity) + item.extraPrice;
    }
    double taxAmount = subtotal * (profile.taxPercentage / 100);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [profile.themeColor, profile.themeColor.withValues(alpha: 0.85)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: profile.themeShadow,
      ),
      child: Column(
        children: [
          _summaryRow('Subtotal', '${profile.currencySymbol}${subtotal.toStringAsFixed(0)}', Colors.white.withValues(alpha: 0.9)),
          if (profile.taxPercentage > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8.0),
              child: _summaryRow('Tax (${profile.taxPercentage}%)', '${profile.currencySymbol}${taxAmount.toStringAsFixed(0)}', Colors.white.withValues(alpha: 0.9)),
            ),
          const SizedBox(height: 8),
          _summaryRow('Discount', '- ${profile.currencySymbol}${_discountController.text}', Colors.white.withValues(alpha: 0.9)),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(color: Colors.white24, height: 1),
          ),
          _summaryRow('Grand Total', '${profile.currencySymbol}${_amountController.text}', Colors.white, isBold: true),
        ],
      ),
    );
  }

  Widget _summaryRow(String label, String value, Color color, {bool isBold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: color, fontSize: 14, fontWeight: isBold ? FontWeight.bold : FontWeight.w500)),
        Text(value, style: TextStyle(color: color, fontSize: isBold ? 24 : 16, fontWeight: isBold ? FontWeight.w900 : FontWeight.w600)),
      ],
    );
  }

  Widget _buildItemsList(ProfileProvider profile) {
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.cart.length,
      itemBuilder: (context, index) {
        final c = widget.cart[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(boxShadow: profile.themeShadow,
            color: profile.cardColor,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade100),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.item.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: profile.textColor)),
                        Text('${c.variant} | ${c.item.category}', style: TextStyle(fontSize: 10, color: profile.secondaryTextColor)),
                      ],
                    ),
                  ),
                  _qtyBtn(Icons.remove, profile, () => setState(() {
                    if (c.quantity > 1) {
                      c.quantity--;
                    } else {
                      widget.cart.removeAt(index);
                    }
                    _calculateTotal();
                  })),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Column(
                      children: [
                        Text('${c.quantity.toInt()}', style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor, fontSize: 13)),
                        Text(c.unit, style: TextStyle(fontSize: 8, color: profile.secondaryTextColor)),
                      ],
                    ),
                  ),
                  _qtyBtn(Icons.add, profile, () => setState(() {
                    c.quantity++;
                    _calculateTotal();
                  })),
                  const SizedBox(width: 10),
                  Text('${profile.currencySymbol}${(c.price * c.quantity + c.extraPrice).toStringAsFixed(0)}',
                    style: TextStyle(fontWeight: FontWeight.w900, color: profile.themeColor, fontSize: 13)),
                ],
              ),
              const Divider(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _smallEntryField('Price', profile, (val) {
                      setState(() {
                        c.price = double.tryParse(val) ?? c.price;
                        _calculateTotal();
                      });
                    }, initial: c.price.toStringAsFixed(0)),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _smallEntryField('Ex Qty', profile, (val) {
                      setState(() {
                        c.extraPieces = double.tryParse(val) ?? 0;
                      });
                    }, initial: c.extraPieces > 0 ? c.extraPieces.toInt().toString() : ''),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: _smallEntryField('Ex Rs', profile, (val) {
                      setState(() {
                        c.extraPrice = double.tryParse(val) ?? 0;
                        _calculateTotal();
                      });
                    }, initial: c.extraPrice > 0 ? c.extraPrice.toInt().toString() : ''),
                  ),
                ],
              ),
              // logic: Item-wise serving method checkbox
              if (widget.type == 'sale') ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    _servingCheckbox(c, 'Dine-in', profile),
                    const SizedBox(width: 20),
                    _servingCheckbox(c, 'Takeaway', profile),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _servingCheckbox(CartItem item, String method, ProfileProvider profile) {
    bool isSelected = item.servingMethod == method;
    return InkWell(
      onTap: () => setState(() => item.servingMethod = method),
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
                  color: isSelected ? profile.themeColor : profile.secondaryTextColor.withValues(alpha: 0.5),
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
                color: isSelected ? profile.themeColor : profile.secondaryTextColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _smallEntryField(String hint, ProfileProvider profile, Function(String) onChange, {String? initial}) {
    final borderColor = widget.type == 'sale' ? Colors.green : Colors.orange;
    return Container(height: 33,
      child: TextFormField(
        initialValue: initial,
        keyboardType: TextInputType.number,
        onChanged: onChange,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: profile.textColor),
        decoration: InputDecoration(
          labelText: hint,
          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor.withOpacity(0.3))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: borderColor, width: 1.5)),
        ),
      ),
    );
  }

  Widget _qtyBtn(IconData icon, ProfileProvider profile, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: profile.scaffoldColor, shape: BoxShape.circle),
        child: Icon(icon, size: 14, color: profile.textColor),
      ),
    );
  }

  Widget _buildPaymentMethodSelector(Color themeColor, ProfileProvider profile) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: profile.cardColor, borderRadius: BorderRadius.circular(16), border: Border.all(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade100)),
      child: Row(
        children: ['Cash', 'UPI', 'Split', 'Credit'].map((mode) {
          bool isSelected = _paymentMode == mode;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                _paymentMode = mode;
                _calculateTotal();
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? themeColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(mode, textAlign: TextAlign.center,
                  style: TextStyle(color: isSelected ? Colors.white : profile.secondaryTextColor, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBottomActionArea(ProfileProvider profile, bool isSale, bool isPurchase) {
    bool canShowPending = isSale && (widget.existingTransaction == null || widget.existingTransaction?.status == 'pending');

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      decoration: BoxDecoration(
        color: profile.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 20, offset: const Offset(0, -5))],
      ),
      child: SafeArea(
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
                      onPressed: _isLoading ? null : () => _handleSave(isPending: true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueGrey.shade100,
                        foregroundColor: Colors.blueGrey.shade800,
                        minimumSize: const Size(double.infinity, 54),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      child: const Text('PENDING', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13, letterSpacing: 0.5)),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : () => _handleSave(isPending: false),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSale ? Colors.green.shade600 : (isPurchase ? Colors.orange.shade700 : Colors.red.shade600),
                      minimumSize: const Size(double.infinity, 54),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                      shadowColor: (isSale ? Colors.green : Colors.orange).withOpacity(0.3),
                    ),
                    child: _isLoading
                      ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                      : Text(widget.existingTransaction?.status == 'pending' ? 'COMPLETE BILL' : 'CONFIRM BILL',
                          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15, color: Colors.white, letterSpacing: 1)),
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
        // Serving Method Toggle (Radio button style toggle)
        Expanded(
          flex: 2,
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: profile.scaffoldColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade200),
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
                        color: isSelected ? profile.themeColor : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(method, textAlign: TextAlign.center,
                        style: TextStyle(color: isSelected ? Colors.white : profile.secondaryTextColor, fontWeight: FontWeight.bold, fontSize: 11)),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Table Picker Dropdown (Same size as toggle)
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            decoration: BoxDecoration(
              color: profile.scaffoldColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade200),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedTable,
                isExpanded: true,
                icon: Icon(Icons.keyboard_arrow_down, size: 18, color: profile.themeColor),
                style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold, fontSize: 13),
                dropdownColor: profile.cardColor,
                items: List.generate(profile.totalTables, (i) => (i + 1).toString())
                    .map((t) => DropdownMenuItem(value: t, child: Text('T-$t')))
                    .toList(),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedTable = val);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _upiSplitField(ProfileProvider profileProvider) {
    return _entryField(_upiSplitController, 'UPI Paid', Icons.qr_code_rounded, Colors.blue, profileProvider, onChanged: (val) {
      double total = double.tryParse(_amountController.text) ?? 0;
      double upi = double.tryParse(val) ?? 0;
      if (upi > total) upi = total;
      _cashSplitController.text = (total - upi).toStringAsFixed(0);
    });
  }

  Widget _entryField(TextEditingController controller, String label, IconData icon, Color themeColor, ProfileProvider profile, {TextInputType type = TextInputType.number, Function(String)? onChanged}) {
    return TextFormField(
      controller: controller,
      keyboardType: type,
      onChanged: onChanged,
      onTap: () {
        if (controller.text == '0' || controller.text == '0.0') {
          controller.clear();
        }
      },
      style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: themeColor),
      ),
    );
  }

  Future<void> _handleSave({bool isPending = false}) async {
    final totalAmt = double.tryParse(_amountController.text) ?? 0;
    if (totalAmt <= 0) return;

    setState(() => _isLoading = true);
    try {
      final txProvider = Provider.of<TransactionProvider>(context, listen: false);
      final itemProvider = Provider.of<ItemProvider>(context, listen: false);

      String description = jsonEncode(widget.cart.map((e) => {
        'id': e.item.id,
        'name': e.item.name,
        'qty': e.quantity,
        'variant': e.variant,
        'price': e.price,
        'extra_qty': e.extraPieces,
        'extra_price': e.extraPrice,
        'serving_method': e.servingMethod, // Item-wise value
        'table_number': _selectedTable, // Global value
      }).toList());

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
        customerContact: _contactController.text.trim(),
        cashAmount: _paymentMode == 'Split' ? (double.tryParse(_cashSplitController.text) ?? 0) : (_paymentMode == 'Cash' ? totalAmt : 0),
        upiAmount: _paymentMode == 'Split' ? (double.tryParse(_upiSplitController.text) ?? 0) : (_paymentMode == 'UPI' ? totalAmt : 0),
        status: isPending ? 'pending' : 'completed',
      );

      if (widget.existingTransaction == null) {
        await txProvider.addTransaction(txData, itemProvider);
        if (isPending && txData.id != null) {
          await NotificationService().scheduleRepeatingReminder(
            txData.id!,
            'Pending Order Reminder',
            'Order for ${txData.customerContact.isNotEmpty ? txData.customerContact : "Customer"} (₹${totalAmt.toStringAsFixed(0)}) is still pending.',
          );
        }
      } else {
        await txProvider.updateTransaction(txData, itemProvider, oldTx: widget.existingTransaction);
        if (!isPending && txData.id != null) {
          await NotificationService().cancelOrderReminders(txData.id!);
        } else if (isPending && txData.id != null) {
           await NotificationService().cancelOrderReminders(txData.id!);
           await NotificationService().scheduleRepeatingReminder(
            txData.id!,
            'Pending Order Reminder',
            'Order for ${txData.customerContact.isNotEmpty ? txData.customerContact : "Customer"} (₹${totalAmt.toStringAsFixed(0)}) is still pending.',
          );
        }
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
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
