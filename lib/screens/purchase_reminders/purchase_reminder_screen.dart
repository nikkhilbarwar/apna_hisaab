import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/widgets/app_bottom_sheet.dart';
import '../../models/purchase_reminder_model.dart';
import '../../providers/purchase_reminder_provider.dart';
import '../../providers/profile_provider.dart';
import '../../providers/category_provider.dart';
import '../../utils/report_helper.dart';
import '../daily_entry/entry_screen.dart';

class PurchaseReminderScreen extends StatefulWidget {
  const PurchaseReminderScreen({super.key});

  @override
  State<PurchaseReminderScreen> createState() => PurchaseReminderScreenState();
}

class PurchaseReminderScreenState extends State<PurchaseReminderScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _tabs = ['Today', 'Upcoming', 'Overdue', 'Completed'];
  final Set<int> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
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

  void _showBulkDeleteConfirm(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final provider =
        Provider.of<PurchaseReminderProvider>(context, listen: false);

    AppBottomSheet.showAction(
      context: context,
      profile: profile,
      title: 'Delete ${_selectedIds.length} items?',
      message: 'Are you sure you want to delete all selected items permanently?',
      confirmLabel: 'DELETE',
      isDestructive: true,
      icon: Icons.delete_sweep_rounded,
    ).then((confirmed) {
      if (confirmed == true) {
        provider.deleteMultipleReminders(_selectedIds.toList());
        setState(() => _selectedIds.clear());
      }
    });
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
    final bool isSelectionMode = _selectedIds.isNotEmpty;

    return Scaffold(
      backgroundColor: profile.scaffoldColor,
      appBar: AppBar(
        leading: isSelectionMode 
          ? IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => setState(() => _selectedIds.clear()))
          : null,
        title: isSelectionMode 
          ? Text('${_selectedIds.length} SELECTED', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.white))
          : const Text('PURCHASE LIST', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, letterSpacing: 1, color: Colors.white)),
        actions: [
          if (isSelectionMode)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.white),
              onPressed: () => _showBulkDeleteConfirm(context),
            ),
        ],
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [themeColor.withValues(alpha: 0.8), themeColor]),
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
          tabs: _tabs.map((t) => Tab(text: t.toUpperCase())).toList(),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: _tabs.map((t) => _ReminderList(
          filter: t,
          selectedIds: _selectedIds,
          onToggle: _toggleSelection,
        )).toList(),
      ),
      floatingActionButton: isSelectionMode ? null : FloatingActionButton.extended(
        onPressed: () => showReminderDialog(context),
        backgroundColor: themeColor,
        icon: const Icon(Icons.add_task_rounded, color: Colors.white),
        label: const Text('ADD NEW', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
      ),
    );
  }

  void showReminderDialog(BuildContext context, {PurchaseReminderModel? editReminder}) {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    final catProvider = Provider.of<CategoryProvider>(context, listen: false);
    
    final nameController = TextEditingController(text: editReminder?.itemName);
    final qtyController = TextEditingController(text: editReminder?.quantity.toString());
    final noteController = TextEditingController(text: editReminder?.note);
    
    String selectedCategory = editReminder?.category ?? (catProvider.categories.isNotEmpty ? catProvider.categories.first.name : 'General');
    String priority = editReminder?.priority ?? 'Medium';
    DateTime selectedDate = editReminder?.dueDate ?? DateTime.now();
    TimeOfDay selectedTime = TimeOfDay.fromDateTime(editReminder?.dueDate ?? DateTime.now());

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Container(
          decoration: BoxDecoration(color: profile.cardColor, borderRadius: const BorderRadius.vertical(top: Radius.circular(32))),
          padding: EdgeInsets.fromLTRB(24, 24, 24, MediaQuery.of(context).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: profile.secondaryTextColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 24),
                Text(editReminder == null ? 'Plan New Purchase' : 'Edit Planned Purchase', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: profile.textColor)),
                const SizedBox(height: 24),
                
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Item Name', prefixIcon: Icon(Icons.shopping_basket_outlined)),
                  style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: qtyController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Qty Required'),
                        style: TextStyle(color: profile.textColor, fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(color: profile.scaffoldColor, borderRadius: BorderRadius.circular(16)),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: selectedCategory,
                            isExpanded: true,
                            dropdownColor: profile.cardColor,
                            items: catProvider.categories.map((c) => DropdownMenuItem(value: c.name, child: Text(c.name, style: const TextStyle(fontSize: 12)))).toList(),
                            onChanged: (v) => setSheetState(() => selectedCategory = v!),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final d = await ReportHelper.showAppDatePicker(context, selectedDate, profile.themeColor);
                          if (d != null) setSheetState(() => selectedDate = d);
                        },
                        child: _dateTimeBox(DateFormat('dd MMM yyyy').format(selectedDate), Icons.calendar_month, profile),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          final t = await showTimePicker(
                            context: context, 
                            initialTime: selectedTime,
                            builder: (context, child) => Theme(
                              data: Theme.of(context).copyWith(
                                colorScheme: profile.isDarkMode 
                                  ? ColorScheme.dark(primary: profile.themeColor, onPrimary: Colors.white, surface: profile.cardColor)
                                  : ColorScheme.light(primary: profile.themeColor),
                              ),
                              child: child!,
                            ),
                          );
                          if (t != null) setSheetState(() => selectedTime = t);
                        },
                        child: _dateTimeBox(selectedTime.format(context), Icons.access_time, profile),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                Text('PRIORITY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, color: profile.secondaryTextColor, letterSpacing: 1)),
                const SizedBox(height: 12),
                Row(
                  children: ['Low', 'Medium', 'High'].map((p) {
                    bool isSel = priority == p;
                    Color c = p == 'High' ? Colors.red : (p == 'Medium' ? Colors.orange : Colors.blue);
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setSheetState(() => priority = p),
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: isSel ? c : c.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: c.withValues(alpha: 0.3)),
                          ),
                          child: Center(child: Text(p, style: TextStyle(color: isSel ? Colors.white : c, fontWeight: FontWeight.bold, fontSize: 12))),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                
                ElevatedButton(
                  onPressed: () {
                    if (nameController.text.isEmpty) return;
                    final reminder = PurchaseReminderModel(
                      id: editReminder?.id,
                      itemName: nameController.text,
                      category: selectedCategory,
                      quantity: double.tryParse(qtyController.text) ?? 0,
                      dueDate: DateTime(selectedDate.year, selectedDate.month, selectedDate.day, selectedTime.hour, selectedTime.minute),
                      priority: priority,
                      note: noteController.text,
                      status: editReminder?.status ?? 'pending',
                    );
                    if (editReminder == null) {
                      Provider.of<PurchaseReminderProvider>(context, listen: false).addReminder(reminder);
                    } else {
                      Provider.of<PurchaseReminderProvider>(context, listen: false).updateReminder(reminder);
                    }
                    Navigator.pop(ctx);
                  },
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 56)),
                  child: Text(editReminder == null ? 'SAVE REMINDER' : 'UPDATE REMINDER', style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dateTimeBox(String text, IconData icon, ProfileProvider profile) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: profile.scaffoldColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: profile.themeColor),
          const SizedBox(width: 12),
          Text(text, style: TextStyle(fontWeight: FontWeight.bold, color: profile.textColor, fontSize: 13)),
        ],
      ),
    );
  }
}

class _ReminderList extends StatelessWidget {
  final String filter;
  final Set<int> selectedIds;
  final Function(int) onToggle;

  const _ReminderList({
    required this.filter,
    required this.selectedIds,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PurchaseReminderProvider>(context);
    final reminders = provider.getFilteredReminders(filter);
    final profile = Provider.of<ProfileProvider>(context);

    if (reminders.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_turned_in_outlined, size: 64, color: profile.secondaryTextColor.withValues(alpha: 0.1)),
            const SizedBox(height: 16),
            Text('No reminders found in $filter', style: TextStyle(color: profile.secondaryTextColor, fontWeight: FontWeight.bold)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: reminders.length,
      itemBuilder: (context, index) {
        final r = reminders[index];
        return _ReminderCard(
          reminder: r,
          isSelected: selectedIds.contains(r.id),
          isSelectionMode: selectedIds.isNotEmpty,
          onToggle: () => onToggle(r.id!),
        );
      },
    );
  }
}

class _ReminderCard extends StatelessWidget {
  final PurchaseReminderModel reminder;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback onToggle;

  const _ReminderCard({
    required this.reminder,
    this.isSelected = false,
    this.isSelectionMode = false,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context);
    final provider = Provider.of<PurchaseReminderProvider>(context, listen: false);
    
    Color priorityColor = reminder.priority == 'High' ? Colors.red : (reminder.priority == 'Medium' ? Colors.orange : Colors.blue);
    bool isCompleted = reminder.status != 'pending';

    return GestureDetector(
      onLongPress: onToggle,
      onTap: isSelectionMode ? onToggle : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: isSelected ? profile.themeColor.withValues(alpha: 0.1) : profile.cardColor,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: isSelected 
              ? profile.themeColor 
              : (isCompleted ? (reminder.status == 'bought' ? Colors.green : Colors.grey).withValues(alpha: 0.2) : profile.isDarkMode ? Colors.white10 : Colors.grey.shade100),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 10, offset: const Offset(0, 4))],
        ),
        child: Column(
          children: [
            ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
              leading: isSelectionMode 
                ? Icon(isSelected ? Icons.check_circle_rounded : Icons.radio_button_off_rounded, color: isSelected ? profile.themeColor : profile.secondaryTextColor)
                : Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: priorityColor.withValues(alpha: 0.1), shape: BoxShape.circle),
                    child: Icon(Icons.shopping_cart_outlined, color: priorityColor, size: 20),
                  ),
              title: Text(reminder.itemName, style: TextStyle(fontWeight: FontWeight.w900, color: isCompleted ? profile.secondaryTextColor : profile.textColor, decoration: isCompleted ? TextDecoration.lineThrough : null)),
              subtitle: Text('${reminder.quantity} Required • ${reminder.category}', style: TextStyle(fontSize: 12, color: profile.secondaryTextColor)),
              trailing: isSelectionMode ? null : PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, color: profile.secondaryTextColor),
                onSelected: (v) {
                  if (v == 'edit') {
                    context.findAncestorStateOfType<PurchaseReminderScreenState>()?.showReminderDialog(context, editReminder: reminder);
                  } else if (v == 'skip') {
                    reminder.status = 'skipped';
                    provider.updateReminder(reminder);
                  } else if (v == 'delete') {
                    _showDeleteConfirm(context, provider);
                  } else if (v == 'reset') {
                    reminder.status = 'pending';
                    provider.updateReminder(reminder);
                  }
                },
                itemBuilder: (context) => [
                  if (!isCompleted) const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit_outlined, size: 18), SizedBox(width: 8), Text('Edit')])),
                  if (!isCompleted) const PopupMenuItem(value: 'skip', child: Row(children: [Icon(Icons.block_flipped, size: 18), SizedBox(width: 8), Text('Skip/Cancel')])),
                  if (isCompleted) const PopupMenuItem(value: 'reset', child: Row(children: [Icon(Icons.restore_rounded, size: 18), SizedBox(width: 8), Text('Mark Pending')])),
                  const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, color: Colors.red, size: 18), SizedBox(width: 8), Text('Delete Permanent', style: TextStyle(color: Colors.red))])),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Icon(Icons.event, size: 14, color: profile.secondaryTextColor),
                  const SizedBox(width: 6),
                  Text(DateFormat('dd MMM, hh:mm a').format(reminder.dueDate), style: TextStyle(fontSize: 11, color: profile.secondaryTextColor, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  if (!isCompleted)
                    ElevatedButton(
                      onPressed: isSelectionMode ? null : () async {
                        bool? purchased = await Navigator.push(context, MaterialPageRoute(builder: (c) => EntryScreen(
                          initialType: 'purchase',
                          initialCategory: reminder.category,
                        )));
                        
                        if (purchased == true) {
                          reminder.status = 'bought';
                          provider.updateReminder(reminder);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: profile.themeColor,
                        minimumSize: const Size(80, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('BOUGHT IT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  if (reminder.status == 'skipped')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                      child: const Text('SKIPPED', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                  if (reminder.status == 'bought')
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(color: Colors.green.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                      child: const Text('PURCHASED', style: TextStyle(color: Colors.green, fontSize: 10, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteConfirm(BuildContext context, PurchaseReminderProvider provider) {
    final profile = Provider.of<ProfileProvider>(context, listen: false);
    AppBottomSheet.showAction(
      context: context,
      profile: profile,
      title: 'Delete Reminder?',
      message: 'Are you sure you want to permanently delete this planning entry?',
      confirmLabel: 'DELETE',
      isDestructive: true,
      icon: Icons.delete_outline,
    ).then((confirmed) {
      if (confirmed == true) {
        provider.deleteReminder(reminder.id!);
      }
    });
  }
}
