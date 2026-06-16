import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../models/supplier_model.dart';
import '../core/database/database_helper.dart';
import '../services/firebase_service.dart';

class SupplierProvider with ChangeNotifier {
  List<SupplierModel> _suppliers = [];
  final FirebaseService _firebaseService = FirebaseService();
  bool _isSyncing = false;

  List<SupplierModel> get suppliers => _suppliers.where((s) => s.isDeleted == 0).toList();
  List<SupplierModel> get deletedSuppliers => _suppliers.where((s) => s.isDeleted == 1).toList();
  List<SupplierModel> get allSuppliers => _suppliers;
  bool get isSyncing => _isSyncing;

  SupplierProvider() {
    fetchSuppliers();
    _setupConnectivityListener();
  }

  void _setupConnectivityListener() {
    Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.any((result) => result != ConnectivityResult.none)) {
        syncAllPendingSuppliers();
      }
    });
  }

  Future<void> fetchSuppliers() async {
    try {
      _suppliers = await DatabaseHelper.instance.getAllSuppliers();
      notifyListeners();
    } catch (e) {
      debugPrint("Error fetching suppliers: $e");
    }
  }

  Future<void> syncAllPendingSuppliers() async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final unsynced = await DatabaseHelper.instance.getUnsyncedData('suppliers');
      for (var map in unsynced) {
        final supplier = SupplierModel.fromMap(map);
        await _firebaseService.syncSupplier(supplier);
        await DatabaseHelper.instance.updateSyncStatus('suppliers', supplier.id!, 1);
      }
      await fetchSuppliers();
    } catch (e) {
      debugPrint("Background Supplier Sync Error: $e");
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> addSupplier(SupplierModel supplier) async {
    try {
      supplier.isSynced = 0;
      supplier.updatedAt = DateTime.now();
      int id = await DatabaseHelper.instance.insertSupplier(supplier);
      supplier.id = id;
      await fetchSuppliers();
      
      _firebaseService.syncSupplier(supplier).then((_) {
        DatabaseHelper.instance.updateSyncStatus('suppliers', id, 1);
      }).catchError((e) {
        debugPrint("Immediate Supplier Sync Error: $e");
        return null;
      });
    } catch (e) {
      debugPrint("Error adding supplier: $e");
    }
  }

  Future<void> updateSupplier(SupplierModel supplier) async {
    try {
      supplier.isSynced = 0;
      supplier.updatedAt = DateTime.now();
      await DatabaseHelper.instance.updateSupplier(supplier);
      await fetchSuppliers();
      
      _firebaseService.syncSupplier(supplier).then((_) {
        DatabaseHelper.instance.updateSyncStatus('suppliers', supplier.id!, 1);
      }).catchError((e) {
        debugPrint("Update Supplier Sync Error: $e");
        return null;
      });
    } catch (e) {
      debugPrint("Error updating supplier: $e");
    }
  }

  Future<void> softDeleteSupplier(int id) async {
    try {
      await DatabaseHelper.instance.softDeleteSupplier(id);
      int index = _suppliers.indexWhere((s) => s.id == id);
      if (index != -1) {
        _suppliers[index].isDeleted = 1;
        _suppliers[index].deletedAt = DateTime.now();
        _suppliers[index].updatedAt = DateTime.now();
        _suppliers[index].isSynced = 0;
        
        try {
          await _firebaseService.syncSupplier(_suppliers[index]);
          await DatabaseHelper.instance.updateSyncStatus('suppliers', id, 1);
        } catch (e) {
          debugPrint("Soft Delete Supplier Sync Error: $e");
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Error soft deleting supplier: $e");
    }
  }

  Future<void> restoreSupplier(int id) async {
    try {
      await DatabaseHelper.instance.restoreSupplier(id);
      int index = _suppliers.indexWhere((s) => s.id == id);
      if (index != -1) {
        _suppliers[index].isDeleted = 0;
        _suppliers[index].deletedAt = null;
        _suppliers[index].updatedAt = DateTime.now();
        _suppliers[index].isSynced = 0;
        
        try {
          await _firebaseService.syncSupplier(_suppliers[index]);
          await DatabaseHelper.instance.updateSyncStatus('suppliers', id, 1);
        } catch (e) {
          debugPrint("Restore Supplier Sync Error: $e");
        }
      }
      notifyListeners();
    } catch (e) {
      debugPrint("Error restoring supplier: $e");
    }
  }

  Future<void> permanentDeleteSupplier(int id) async {
    try {
      await DatabaseHelper.instance.permanentDeleteSupplier(id);
      await _firebaseService.deleteSupplier(id);
      _suppliers.removeWhere((s) => s.id == id);
      notifyListeners();
    } catch (e) {
      debugPrint("Error permanent deleting supplier: $e");
    }
  }
}
