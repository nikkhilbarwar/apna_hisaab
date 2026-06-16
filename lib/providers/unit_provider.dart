import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/unit_model.dart';
import '../core/database/database_helper.dart';

class UnitProvider with ChangeNotifier {
  List<UnitModel> _units = [];

  List<UnitModel> get units => _units.where((u) => u.isDeleted == 0).toList();
  List<UnitModel> get allUnits => _units;

  UnitProvider() {
    fetchUnits();
  }

  Future<void> fetchUnits() async {
    try {
      final data = await DatabaseHelper.instance.getAllUnits();
      _units = data.map((e) => UnitModel.fromMap(e)).toList();
      
      if (_units.isEmpty) {
        await _insertDefaultUnits();
      } else {
        await _cleanupDuplicateUnits();
        notifyListeners();
      }
    } catch (e) {
      debugPrint("Error fetching units: $e");
    }
  }

  Future<void> _cleanupDuplicateUnits() async {
    bool changed = false;
    final Map<String, int> uniqueNames = {};
    final List<int> idsToDelete = [];

    for (var unit in _units) {
      if (unit.isDeleted == 1) continue;
      String name = unit.name.toLowerCase().trim();
      if (uniqueNames.containsKey(name)) {
        idsToDelete.add(unit.id!);
        changed = true;
      } else {
        uniqueNames[name] = unit.id!;
      }
    }

    if (changed) {
      for (var id in idsToDelete) {
        await DatabaseHelper.instance.permanentDeleteUnit(id);
      }
      final data = await DatabaseHelper.instance.getAllUnits();
      _units = data.map((e) => UnitModel.fromMap(e)).toList();
    }
  }

  Future<void> _insertDefaultUnits() async {
    List<String> defaults = ['Plate', "Pc's", 'Packet', 'kg', 'gm', 'liter', 'ml'];
    final existingUnits = _units.map((u) => u.name.toLowerCase()).toSet();
    
    for (var name in defaults) {
      if (!existingUnits.contains(name.toLowerCase())) {
        await addUnit(name);
      }
    }
  }

  Future<void> addUnit(String name) async {
    if (_units.any((u) => u.name.toLowerCase() == name.toLowerCase() && u.isDeleted == 0)) return;
    
    // Check if a deleted unit with this name exists, if so restore it
    int existingDeletedIndex = _units.indexWhere((u) => u.name.toLowerCase() == name.toLowerCase() && u.isDeleted == 1);
    if (existingDeletedIndex != -1) {
      await restoreUnit(_units[existingDeletedIndex].id!);
      return;
    }

    int id = await DatabaseHelper.instance.insertUnit(name);
    final newUnit = UnitModel(id: id, name: name, isSynced: 0);
    _units.add(newUnit);
    
    _syncUnitToFirebase(newUnit);
    notifyListeners();
  }

  Future<void> softDeleteUnit(int id) async {
    try {
      await DatabaseHelper.instance.softDeleteUnit(id);
      int index = _units.indexWhere((u) => u.id == id);
      if (index != -1) {
        _units[index].isDeleted = 1;
        _units[index].isSynced = 0;
        _units[index].updatedAt = DateTime.now();
        _units[index].deletedAt = DateTime.now();
        _syncUnitToFirebase(_units[index]);
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Error soft deleting unit: $e");
    }
  }

  Future<void> restoreUnit(int id) async {
    try {
      await DatabaseHelper.instance.restoreUnit(id);
      int index = _units.indexWhere((u) => u.id == id);
      if (index != -1) {
        _units[index].isDeleted = 0;
        _units[index].isSynced = 0;
        _units[index].updatedAt = DateTime.now();
        _units[index].deletedAt = null;
        _syncUnitToFirebase(_units[index]);
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Error restoring unit: $e");
    }
  }

  Future<void> permanentDeleteUnit(int id) async {
    try {
      await DatabaseHelper.instance.permanentDeleteUnit(id);
      _units.removeWhere((u) => u.id == id);
      
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .collection('units')
            .doc(id.toString())
            .delete();
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Error permanent deleting unit: $e");
    }
  }

  // Backwards compatibility
  Future<void> deleteUnit(int id) async => await softDeleteUnit(id);

  Future<void> _syncUnitToFirebase(UnitModel unit) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('units')
          .doc(unit.id.toString())
          .set(unit.toMap());
      
      await DatabaseHelper.instance.updateSyncStatus('units', unit.id!, 1);
      int index = _units.indexWhere((u) => u.id == unit.id);
      if (index != -1) {
        _units[index].isSynced = 1;
      }
    } catch (e) {
      debugPrint("Unit Sync Error: $e");
    }
  }
}
