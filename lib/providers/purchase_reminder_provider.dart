import 'package:flutter/material.dart';
import '../models/purchase_reminder_model.dart';
import '../core/database/database_helper.dart';

class PurchaseReminderProvider with ChangeNotifier {
  List<PurchaseReminderModel> _reminders = [];
  bool _isLoading = false;

  List<PurchaseReminderModel> get reminders => _reminders;
  bool get isLoading => _isLoading;

  PurchaseReminderProvider() {
    fetchReminders();
  }

  Future<void> fetchReminders() async {
    _isLoading = true;
    notifyListeners();
    try {
      _reminders = await DatabaseHelper.instance.getAllPurchaseReminders();
    } catch (e) {
      debugPrint("Error fetching reminders: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addReminder(PurchaseReminderModel reminder) async {
    try {
      int id = await DatabaseHelper.instance.insertPurchaseReminder(reminder);
      reminder.id = id;
      _reminders.add(reminder);
      notifyListeners();
      // TODO: Trigger background sync to Firebase
    } catch (e) {
      debugPrint("Error adding reminder: $e");
    }
  }

  Future<void> updateReminder(PurchaseReminderModel reminder) async {
    try {
      await DatabaseHelper.instance.updatePurchaseReminder(reminder);
      int index = _reminders.indexWhere((r) => r.id == reminder.id);
      if (index != -1) {
        _reminders[index] = reminder;
        notifyListeners();
        // TODO: Trigger background sync to Firebase
      }
    } catch (e) {
      debugPrint("Error updating reminder: $e");
    }
  }

  Future<void> softDeleteReminder(int id) async {
    try {
      await DatabaseHelper.instance.softDeletePurchaseReminder(id);
      _reminders.removeWhere((r) => r.id == id);
      notifyListeners();
      // TODO: Trigger background sync to Firebase
    } catch (e) {
      debugPrint("Error soft deleting reminder: $e");
    }
  }

  Future<void> restoreReminder(int id) async {
    try {
      await DatabaseHelper.instance.restorePurchaseReminder(id);
      await fetchReminders();
    } catch (e) {
      debugPrint("Error restoring reminder: $e");
    }
  }

  Future<void> deleteReminder(int id) async {
    try {
      await DatabaseHelper.instance.permanentDeletePurchaseReminder(id);
      _reminders.removeWhere((r) => r.id == id);
      notifyListeners();
    } catch (e) {
      debugPrint("Error deleting reminder: $e");
    }
  }

  Future<void> deleteMultipleReminders(List<int> ids) async {
    try {
      for (var id in ids) {
        await DatabaseHelper.instance.permanentDeletePurchaseReminder(id);
      }
      _reminders.removeWhere((r) => ids.contains(r.id));
      notifyListeners();
    } catch (e) {
      debugPrint("Error deleting multiple reminders: $e");
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
