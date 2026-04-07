import 'package:flutter/material.dart';
import '../models/purchase_reminder_model.dart';
import '../core/database/database_helper.dart';

class PurchaseReminderProvider with ChangeNotifier {
  List<PurchaseReminderModel> _reminders = [];
  bool _isSyncing = false;

  List<PurchaseReminderModel> get reminders => _reminders;
  bool get isSyncing => _isSyncing;

  PurchaseReminderProvider() {
    fetchReminders();
  }

  Future<void> fetchReminders() async {
    try {
      final db = await DatabaseHelper.instance.database;
      final List<Map<String, dynamic>> maps = await db.query('purchase_reminders', orderBy: 'due_date ASC');
      _reminders = maps.map((m) => PurchaseReminderModel.fromMap(m)).toList();
      notifyListeners();
    } catch (e) {
      debugPrint("Error fetching reminders: $e");
    }
  }

  Future<void> addReminder(PurchaseReminderModel reminder) async {
    try {
      final db = await DatabaseHelper.instance.database;
      int id = await db.insert('purchase_reminders', reminder.toMap());
      reminder.id = id;
      _reminders.add(reminder);
      notifyListeners();
    } catch (e) {
      debugPrint("Error adding reminder: $e");
    }
  }

  Future<void> updateReminder(PurchaseReminderModel reminder) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.update('purchase_reminders', reminder.toMap(), where: 'id = ?', whereArgs: [reminder.id]);
      int index = _reminders.indexWhere((r) => r.id == reminder.id);
      if (index != -1) {
        _reminders[index] = reminder;
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error updating reminder: $e");
    }
  }

  Future<void> deleteReminder(int id) async {
    try {
      final db = await DatabaseHelper.instance.database;
      await db.delete('purchase_reminders', where: 'id = ?', whereArgs: [id]);
      _reminders.removeWhere((r) => r.id == id);
      notifyListeners();
    } catch (e) {
      debugPrint("Error deleting reminder: $e");
    }
  }

  List<PurchaseReminderModel> getFilteredReminders(String filter) {
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    DateTime tomorrow = today.add(const Duration(days: 1));

    switch (filter) {
      case 'Today':
        return _reminders.where((r) => r.status == 'pending' && 
          r.dueDate.isAfter(today.subtract(const Duration(seconds: 1))) && 
          r.dueDate.isBefore(tomorrow)).toList();
      case 'Upcoming':
        return _reminders.where((r) => r.status == 'pending' && r.dueDate.isAfter(tomorrow)).toList();
      case 'Overdue':
        return _reminders.where((r) => r.status == 'pending' && r.dueDate.isBefore(today)).toList();
      case 'Completed':
        return _reminders.where((r) => r.status != 'pending').toList();
      default:
        return _reminders;
    }
  }
}
