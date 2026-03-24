import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/item_provider.dart';
import '../../providers/profile_provider.dart';
import '../../models/transaction_model.dart';
import '../daily_entry/entry_screen.dart';

class HistoryScreen extends StatefulWidget {
  final bool isPopup;
  const HistoryScreen({super.key, this.isPopup = false});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final Set<int> _selectedIds = {};
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _selectedIds.clear();
          _isSearching = false;
          _searchQuery = "";
          _searchController.clear();
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSelection(int id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
    });
  }

  void _bulkDelete() {
    final txProvider = Provider.of<TransactionProvider>(context, listen: false);
    final itemProvider = Provider.of<ItemProvider>(context, listen: false);
    
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${_selectedIds.length} Records?'),
        content: const Text('Are you sure you want to move these items to Trash?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          TextButton(
            onPressed: () async {
              for (int id in _selectedIds) {
                await txProvider.softDeleteTransaction(id, itemProvider);
              }
              setState(() => _selectedIds.clear());
              if (mounted) Navigator.pop(ctx);
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context);
    final themeColor = profile.themeColor;
    final isSelectionMode = _selectedIds.isNotEmpty;

    return Scaffold(
      backgroundColor: profile.scaffoldColor,
      appBar: widget.isPopup ? null : AppBar(
        backgroundColor: isSelectionMode ? Colors.red.shade700 : profile.cardColor,
        foregroundColor: isSelectionMode ? Colors.white : profile.textColor,
        title: _isSearching 
          ? TextField(
              controller: _searchController,
              autofocus: true,
              style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                hintText: "Search by item name...",
                border: InputBorder.none,
                focusedBorder: InputBorder.none,
                enabledBorder: InputBorder.none,
                fillColor: Colors.transparent,
              ),
              onChanged: (value) => setState(() => _searchQuery = value),
            )
          : Text(isSelectionMode ? '${_selectedIds.length} SELECTED' : 'HISTORY & TRASH', 
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        leading: isSelectionMode 
            ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _selectedIds.clear()))
            : (_isSearching ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => setState(() => _isSearching = false)) : null),
        actions: [
          if (isSelectionMode)
            IconButton(icon: const Icon(Icons.delete_sweep_rounded), onPressed: _bulkDelete)
          else
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
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: isSelectionMode ? Colors.white : themeColor,
          labelColor: isSelectionMode ? Colors.white : themeColor,
          unselectedLabelColor: isSelectionMode ? Colors.white70 : profile.secondaryTextColor,
          tabs: const [
            Tab(text: 'Sales'),
            Tab(text: 'Expenses'),
            Tab(text: 'Trash 🗑️'),
          ],
        ),
        elevation: 0,
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _HistoryList(type: 'sale', selectedIds: _selectedIds, onToggle: _toggleSelection, searchQuery: _searchQuery),
          _HistoryList(type: 'expense', selectedIds: _selectedIds, onToggle: _toggleSelection, searchQuery: _searchQuery),
          _HistoryList(type: 'trash', selectedIds: _selectedIds, onToggle: _toggleSelection, searchQuery: _searchQuery),
        ],
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  final String type;
  final Set<int> selectedIds;
  final Function(int) onToggle;
  final String searchQuery;

  const _HistoryList({required this.type, required this.selectedIds, required this.onToggle, required this.searchQuery});

  @override
  Widget build(BuildContext context) {
    final txProvider = Provider.of<TransactionProvider>(context);
    final profile = Provider.of<ProfileProvider>(context);
    
    List<TransactionModel> filteredList;
    if (type == 'trash') {
      filteredList = txProvider.deletedTransactions;
    } else {
      filteredList = txProvider.transactions.where((tx) {
        if (type == 'sale') return tx.type == 'sale';
        return tx.type == 'expense' || tx.type == 'purchase';
      }).toList();
    }

    if (searchQuery.isNotEmpty) {
      filteredList = filteredList.where((tx) {
        if (tx.description.toLowerCase().contains(searchQuery.toLowerCase())) return true;
        if (tx.category.toLowerCase().contains(searchQuery.toLowerCase())) return true;
        return tx.parsedItems.any((item) => 
          (item['name'] ?? '').toString().toLowerCase().contains(searchQuery.toLowerCase())
        );
      }).toList();
    }

    if (filteredList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(searchQuery.isEmpty ? Icons.history_rounded : Icons.search_off_rounded, size: 64, color: profile.secondaryTextColor.withOpacity(0.2)),
            const SizedBox(height: 16),
            Text(searchQuery.isEmpty ? 'No history found' : 'No matches found', style: TextStyle(color: profile.secondaryTextColor, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredList.length,
      itemBuilder: (context, index) {
        final tx = filteredList[index];
        final isSelected = selectedIds.contains(tx.id);
        final isTrash = type == 'trash';
        final isCredit = tx.paymentMode == 'Credit' && tx.remainingCredit > 0;

        return GestureDetector(
          onLongPress: () => onToggle(tx.id!),
          onTap: () {
            if (selectedIds.isNotEmpty) {
              onToggle(tx.id!);
            } else {
              _showTransactionDetailSheet(context, tx);
            }
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: isSelected ? Colors.red.withOpacity(0.05) : profile.cardColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4))],
              border: Border.all(
                color: isSelected ? Colors.red : (isCredit ? Colors.orange.withOpacity(0.5) : (profile.isDarkMode ? Colors.white10 : Colors.grey.shade100)),
                width: (isSelected || isCredit) ? 2 : 1,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isTrash 
                        ? Colors.grey.withOpacity(0.1) 
                        : (tx.type == 'sale' ? Colors.green : Colors.red).withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isTrash ? Icons.delete_outline : (tx.type == 'sale' ? Icons.south_west_rounded : Icons.north_east_rounded), 
                      color: isTrash ? Colors.grey : (tx.type == 'sale' ? Colors.green : Colors.red),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tx.type == 'sale' 
                            ? (tx.parsedItems.isNotEmpty ? (tx.parsedItems[0]['name'] ?? 'Sale Order').toString() : 'Sale Order') 
                            : tx.category, 
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: profile.textColor),
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(DateFormat('dd MMM, hh:mm a').format(tx.date), style: TextStyle(fontSize: 11, color: profile.secondaryTextColor)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${profile.currencySymbol}${tx.amount.toStringAsFixed(0)}', 
                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: isTrash ? Colors.grey : (tx.type == 'sale' ? Colors.green : Colors.red))),
                      if (isCredit)
                        Container(
                          margin: const EdgeInsets.only(top: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.orange.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                          child: Text('DUE: ${tx.remainingCredit.toStringAsFixed(0)}', style: const TextStyle(fontSize: 9, color: Colors.orange, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showTransactionDetailSheet(BuildContext context, TransactionModel tx) {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final txProvider = Provider.of<TransactionProvider>(context, listen: false);
    final itemProvider = Provider.of<ItemProvider>(context, listen: false);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
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
              child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.withOpacity(0.2), borderRadius: BorderRadius.circular(2))),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tx.type == 'sale' ? 'Sale Details' : 'Expense Details', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: profile.textColor)),
                    Text(DateFormat('EEEE, dd MMMM yyyy').format(tx.date), style: TextStyle(color: profile.secondaryTextColor, fontSize: 12)),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: (tx.type == 'sale' ? Colors.green : Colors.red).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(tx.type.toUpperCase(), style: TextStyle(color: tx.type == 'sale' ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('ITEMS LIST', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: profile.secondaryTextColor, letterSpacing: 1)),
            const SizedBox(height: 12),
            ...tx.parsedItems.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text((item['display'] ?? '').toString(), style: TextStyle(color: profile.textColor, fontWeight: FontWeight.w600)),
                      if (item['price'] != null) Text('${profile.currencySymbol}${item['price']}', style: TextStyle(color: profile.secondaryTextColor)),
                    ],
                  ),
                  if (item['serving_method'] != null && item['serving_method'] != '')
                    Padding(
                      padding: const EdgeInsets.only(top: 2.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const SizedBox(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: profile.themeColor.withOpacity(0.05), borderRadius: BorderRadius.circular(4)),
                            child: Text(item['serving_method']!, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: profile.themeColor)),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            )),
            const Divider(height: 32),
            _detailRow('Total Amount', '${profile.currencySymbol}${tx.amount}', isBold: true, color: profile.textColor),
            _detailRow('Payment Mode', tx.paymentMode, color: profile.themeColor),
            if (tx.paymentMode == 'Split') ...[
              _detailRow('Cash Amount', '${profile.currencySymbol}${tx.cashAmount}', color: profile.secondaryTextColor),
              _detailRow('UPI Amount', '${profile.currencySymbol}${tx.upiAmount}', color: profile.secondaryTextColor),
            ],
            if (tx.paymentMode == 'Credit')
              _detailRow('Remaining Credit', '${profile.currencySymbol}${tx.remainingCredit}', color: Colors.orange, isBold: true),
            
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (c) => EntryScreen(transaction: tx)));
                    },
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    label: const Text('EDIT'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      side: const BorderSide(color: Colors.blue),
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      txProvider.softDeleteTransaction(tx.id!, itemProvider);
                    },
                    icon: const Icon(Icons.delete_outline, size: 20),
                    label: const Text('DELETE'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red.shade50,
                      foregroundColor: Colors.red,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _detailRow(String label, String value, {bool isBold = false, Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(value, style: TextStyle(fontWeight: isBold ? FontWeight.w900 : FontWeight.bold, color: color, fontSize: 14)),
        ],
      ),
    );
  }
}
