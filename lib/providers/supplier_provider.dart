import 'package:flutter/material.dart';
import '../models/supplier_model.dart';
import '../core/database/database_helper.dart';
import '../services/firebase_service.dart';

class SupplierProvider with ChangeNotifier {
  List<SupplierModel> _suppliers = [];
  final FirebaseService _firebaseService = FirebaseService();

  List<SupplierModel> get suppliers => _suppliers;

  Future<void> fetchSuppliers() async {
    try {
      _suppliers = await DatabaseHelper.instance.getAllSuppliers();
      notifyListeners();
    } catch (e) {
      print("Error fetching suppliers: $e");
    }
  }

  Future<void> addSupplier(SupplierModel supplier) async {
    try {
      int id = await DatabaseHelper.instance.insertSupplier(supplier);
      supplier.id = id;
      await fetchSuppliers();
      await _firebaseService.syncSupplier(supplier);
    } catch (e) {
      print("Error adding supplier: $e");
    }
  }

  Future<void> updateSupplier(SupplierModel supplier) async {
    try {
      await DatabaseHelper.instance.updateSupplier(supplier);
      await fetchSuppliers();
      await _firebaseService.syncSupplier(supplier);
    } catch (e) {
      print("Error updating supplier: $e");
    }
  }

  Future<void> deleteSupplier(int id) async {
    try {
      await DatabaseHelper.instance.deleteSupplier(id);
      await fetchSuppliers();
    } catch (e) {
      print("Error deleting supplier: $e");
    }
  }
}
