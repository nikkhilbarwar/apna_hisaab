import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/transaction_provider.dart';
import '../../providers/item_provider.dart';
import '../../providers/profile_provider.dart';
import '../../models/transaction_model.dart';
import '../../utils/app_strings.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() => _selectedIds.clear());
      }
    });
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
              Navigator.pop(ctx);
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
        title: Text(isSelectionMode ? '${_selectedIds.length} SELECTED' : 'HISTORY & TRASH', 
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        leading: isSelectionMode 
            ? IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _selectedIds.clear()))
            : null,
        actions: [
          if (isSelectionMode)
            IconButton(icon: const Icon(Icons.delete_sweep_rounded), onPressed: _bulkDelete),
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
      body: Column(
        children: [
          if (widget.isPopup)
            Container(
              color: isSelectionMode ? Colors.red.shade700 : profile.cardColor,
              child: Column(
                children: [
                  if (isSelectionMode)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('${_selectedIds.length} SELECTED', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          Row(
                            children: [
                              IconButton(icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white), onPressed: _bulkDelete),
                              IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => setState(() => _selectedIds.clear())),
                            ],
                          ),
                        ],
                      ),
                    ),
                  TabBar(
                    controller: _tabController,
                    tabs: [
                      Tab(child: Text('Sales', style: TextStyle(color: isSelectionMode ? Colors.white : themeColor, fontWeight: FontWeight.bold))),
                      Tab(child: Text('Expenses', style: TextStyle(color: isSelectionMode ? Colors.white : themeColor, fontWeight: FontWeight.bold))),
                      Tab(child: Text('Trash', style: TextStyle(color: isSelectionMode ? Colors.white : Colors.red, fontWeight: FontWeight.bold))),
                    ],
                    indicatorColor: isSelectionMode ? Colors.white : themeColor,
                  ),
                ],
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _HistoryList(type: 'sale', selectedIds: _selectedIds, onToggle: _toggleSelection),
                _HistoryList(type: 'expense', selectedIds: _selectedIds, onToggle: _toggleSelection),
                _HistoryList(type: 'trash', selectedIds: _selectedIds, onToggle: _toggleSelection),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryList extends StatelessWidget {
  final String type;
  final Set<int> selectedIds;
  final Function(int) onToggle;

  const _HistoryList({required this.type, required this.selectedIds, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final txProvider = Provider.of<TransactionProvider>(context);
    final itemProvider = Provider.of<ItemProvider>(context, listen: false);
    final profile = Provider.of<ProfileProvider>(context);
    final currency = profile.currencySymbol;
    
    List<TransactionModel> filteredList;
    if (type == 'trash') {
      filteredList = txProvider.deletedTransactions;
    } else {
      filteredList = txProvider.transactions.where((tx) {
        if (type == 'sale') return tx.type == 'sale';
        return tx.type == 'expense' || tx.type == 'purchase';
      }).toList();
    }

    if (filteredList.isEmpty) {
      return Center(child: Text(type == 'trash' ? 'Trash is empty' : 'No history found', style: TextStyle(color: profile.secondaryTextColor)));
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
            }
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: isSelected ? Colors.red.withOpacity(0.05) : profile.cardColor,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected ? Colors.red : (isCredit ? Colors.orange.withOpacity(0.5) : (profile.isDarkMode ? Colors.white10 : Colors.grey.shade100)),
                width: (isSelected || isCredit) ? 2 : 1,
              ),
            ),
            child: ExpansionTile(
              enabled: selectedIds.isEmpty, // Disable expansion when selecting
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              collapsedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              leading: isSelected 
                ? const Icon(Icons.check_circle, color: Colors.red)
                : Container(
                  padding: const EdgeInsets.all(8),
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
              title: Text(tx.type == 'sale' ? 'Sale Order' : tx.category, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: profile.textColor)),
              subtitle: Text(DateFormat('dd MMM, hh:mm a').format(tx.date), style: TextStyle(fontSize: 11, color: profile.secondaryTextColor)),
              trailing: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$currency${tx.amount.toStringAsFixed(0)}', 
                    style: TextStyle(fontWeight: FontWeight.bold, color: isTrash ? Colors.grey : (tx.type == 'sale' ? Colors.green : Colors.red))),
                  if (isCredit)
                    Text('DUE: $currency${tx.remainingCredit.toStringAsFixed(0)}', 
                      style: const TextStyle(fontSize: 10, color: Colors.orange, fontWeight: FontWeight.w900)),
                ],
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('DETAILS:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: profile.secondaryTextColor)),
                      const SizedBox(height: 8),
                      ...tx.parsedItems.map((item) => Text(item['display'] ?? '', style: TextStyle(fontSize: 13, color: profile.textColor))),
                      Divider(height: 24, color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade100),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Payment: ${tx.paymentMode}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: profile.textColor)),
                            ],
                          ),
                          Row(
                            children: isTrash ? [
                              IconButton(
                                icon: const Icon(Icons.restore, color: Colors.green),
                                onPressed: () => txProvider.restoreTransaction(tx.id!, itemProvider),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_forever, color: Colors.red),
                                onPressed: () => _confirmPermanentDelete(context, txProvider, tx.id!),
                              ),
                            ] : [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 20, color: Colors.blue),
                                onPressed: () {
                                  Navigator.push(context, MaterialPageRoute(builder: (c) => EntryScreen(transaction: tx)));
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                onPressed: () => txProvider.softDeleteTransaction(tx.id!, itemProvider),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _confirmPermanentDelete(BuildContext context, TransactionProvider provider, int id) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permanent Delete?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CANCEL')),
          TextButton(onPressed: () { provider.deletePermanently(id); Navigator.pop(ctx); }, child: const Text('DELETE', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
  }
}
