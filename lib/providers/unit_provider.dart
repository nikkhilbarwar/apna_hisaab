import 'package:flutter/material.dart';
import '../models/unit_model.dart';
import '../core/database/database_helper.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class UnitProvider with ChangeNotifier {
  List<UnitModel> _units = [];

  List<UnitModel> get units => _units;

  UnitProvider() {
    fetchUnits();
  }

  Future<void> fetchUnits() async {
    final data = await DatabaseHelper.instance.getAllUnits();
    _units = data.map((e) => UnitModel.fromMap(e)).toList();
    
    if (_units.isEmpty) {
      await _insertDefaultUnits();
    } else {
      await _cleanupDuplicateUnits();
      notifyListeners();
    }
  }

  Future<void> _cleanupDuplicateUnits() async {
    bool changed = false;
    final Map<String, int> uniqueNames = {};
    final List<int> idsToDelete = [];

    for (var unit in _units) {
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
        await DatabaseHelper.instance.deleteUnit(id);
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
    if (_units.any((u) => u.name.toLowerCase() == name.toLowerCase())) return;
    
    int id = await DatabaseHelper.instance.insertUnit(name);
    final newUnit = UnitModel(id: id, name: name);
    _units.add(newUnit);
    
    // Sync to Firebase
    _syncUnitToFirebase(newUnit);
    
    notifyListeners();
  }

  Future<void> deleteUnit(int id) async {
    await DatabaseHelper.instance.deleteUnit(id);
    _units.removeWhere((u) => u.id == id);
    
    // Delete from Firebase
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
  }

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
    } catch (e) {
      debugPrint("Unit Sync Error: $e");
    }
  }
}
