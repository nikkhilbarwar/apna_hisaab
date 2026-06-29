import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:apna_hisaab/models/transaction_model.dart';
import 'package:apna_hisaab/models/item_model.dart';
import 'package:apna_hisaab/models/supplier_model.dart';
import 'package:apna_hisaab/models/staff_model.dart';
import 'package:apna_hisaab/models/category_model.dart';
import 'package:apna_hisaab/models/purchase_reminder_model.dart';

import '../../services/firebase_service.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  static String? _currentUserId;
  static String? _currentLicenseId;

  DatabaseHelper._init();

  static void resetDatabase() {
    _database = null;
    _currentUserId = null;
    _currentLicenseId = null;
  }

  Future<Database> get database async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("User not logged in");
    
    // We get licenseId from some global state. 
    // For now assuming it is set in ProfileProvider.activeLicenseKey
    // We use licenseId to partition database files
    final String licenseId = FirebaseService.activeLicenseKey ?? 'NONE';

    if (_currentUserId != user.uid || _currentLicenseId != licenseId) {
      await closeDatabase();
      _currentUserId = user.uid;
      _currentLicenseId = licenseId;
      _database = await _initDB('food_cart_${user.uid}_$licenseId.db');
    }

    if (_database != null) return _database!;
    _database = await _initDB('food_cart_${user.uid}_$licenseId.db');
    return _database!;
  }

  Future<void> closeDatabase() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path, 
      version: 40,
      onCreate: _createDB, 
      onUpgrade: (db, oldVersion, newVersion) async {
        debugPrint("MIGRATION: Upgrading from $oldVersion to $newVersion");
        await _onUpgrade(db, oldVersion, newVersion);
      }
    );
  }

  Future<void> _ensureTableColumn(Database db, String tableName, String columnName, String columnType) async {
    try {
      var tableInfo = await db.rawQuery('PRAGMA table_info($tableName)');
      var columns = tableInfo.map((row) => row['name']).toList();
      if (!columns.contains(columnName)) {
        debugPrint("MIGRATION: Adding column $columnName to $tableName");
        await db.execute('ALTER TABLE $tableName ADD COLUMN $columnName $columnType');
      }
    } catch (e) {
      debugPrint("MIGRATION ERROR: Could not add $columnName to $tableName: $e");
    }
  }

  // Helper to ensure license_id exists in all tables
  Future<void> _addLicenseIdToTables(Database db) async {
    final tables = [
      'transactions', 'items', 'suppliers', 'staff', 
      'categories', 'units', 'purchase_reminders', 'recipes',
      'staff_advance', 'staff_leave'
    ];
    for (var table in tables) {
      await _ensureTableColumn(db, table, 'license_id', 'TEXT DEFAULT "NONE"');
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 40) {
      await _addLicenseIdToTables(db);
    }

    debugPrint("DEBUG: Running migration from $oldVersion to $newVersion");
    
    // Self-healing migration for version 39
    if (oldVersion < 39) {
      final tables = [
        'items', 'transactions', 'categories', 'staff', 'suppliers', 
        'units', 'purchase_reminders', 'recipes', 'staff_advance', 'staff_leave'
      ];

      for (var table in tables) {
        await _ensureTableColumn(db, table, 'is_synced', 'INTEGER DEFAULT 0');
        await _ensureTableColumn(db, table, 'updated_at', 'TEXT');
        
        // Add soft delete columns to relevant tables
        if (table != 'recipes' && table != 'staff_advance' && table != 'staff_leave') {
          await _ensureTableColumn(db, table, 'is_deleted', 'INTEGER DEFAULT 0');
          await _ensureTableColumn(db, table, 'deleted_at', 'TEXT');
        }
      }

      // Additional specific columns that might be missing
      await _ensureTableColumn(db, 'items', 'purchase_price', 'REAL');
      await _ensureTableColumn(db, 'items', 'transport_cost', 'REAL');
      await _ensureTableColumn(db, 'items', 'linked_item_ids', 'TEXT');
      await _ensureTableColumn(db, 'items', 'linked_category_ids', 'TEXT');
      await _ensureTableColumn(db, 'items', 'icon', 'TEXT');
      
      await _ensureTableColumn(db, 'transactions', 'cash_amount', 'REAL DEFAULT 0');
      await _ensureTableColumn(db, 'transactions', 'upi_amount', 'REAL DEFAULT 0');
      await _ensureTableColumn(db, 'transactions', 'customer_contact', 'TEXT DEFAULT ""');
      await _ensureTableColumn(db, 'transactions', 'status', 'TEXT DEFAULT "completed"');

      await _ensureTableColumn(db, 'categories', 'display_order', 'INTEGER DEFAULT 0');
      await _ensureTableColumn(db, 'categories', 'use_category_stock', 'INTEGER DEFAULT 0');
      await _ensureTableColumn(db, 'categories', 'stock_qty', 'REAL DEFAULT 0');
      await _ensureTableColumn(db, 'categories', 'low_stock_limit', 'REAL DEFAULT 10');

      await _ensureTableColumn(db, 'staff', 'role', 'TEXT DEFAULT "Staff"');
      await _ensureTableColumn(db, 'staff', 'is_login_enabled', 'INTEGER DEFAULT 0');
      await _ensureTableColumn(db, 'staff', 'staff_code', 'TEXT DEFAULT ""');
      await _ensureTableColumn(db, 'staff', 'login_pin', 'TEXT DEFAULT ""');
      await _ensureTableColumn(db, 'staff', 'permissions', 'TEXT DEFAULT "{\\"can_sale\\":true,\\"can_stock\\":false,\\"can_reports\\":false}"');
      
      await _ensureTableColumn(db, 'staff_advance', 'status', 'TEXT DEFAULT "pending"');
    }

    if (oldVersion < 19) {
      try { await db.execute('ALTER TABLE categories ADD COLUMN display_order INTEGER DEFAULT 0'); } catch(_) {}
    }
    if (oldVersion < 20) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS units (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT,
          is_synced INTEGER DEFAULT 0
        )
      ''');
    }
    if (oldVersion < 21) {
      try { await db.execute('ALTER TABLE categories ADD COLUMN use_category_stock INTEGER DEFAULT 0'); } catch(_) {}
      try { await db.execute('ALTER TABLE categories ADD COLUMN stock_qty REAL DEFAULT 0'); } catch(_) {}
      try { await db.execute('ALTER TABLE categories ADD COLUMN low_stock_limit REAL DEFAULT 10'); } catch(_) {}
    }
    if (oldVersion < 22) {
      try { await db.execute('ALTER TABLE items ADD COLUMN icon TEXT'); } catch(_) {}
    }
    if (oldVersion < 23) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS purchase_reminders (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          item_id INTEGER,
          item_name TEXT,
          category TEXT,
          quantity REAL,
          expected_price REAL,
          note TEXT,
          priority TEXT,
          due_date TEXT,
          status TEXT,
          is_synced INTEGER DEFAULT 0
        )
      ''');
    }
    if (oldVersion < 24) {
      try { await db.execute('ALTER TABLE staff ADD COLUMN image_path TEXT'); } catch(_) {}
      await db.execute('''
        CREATE TABLE IF NOT EXISTS staff_advance (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          staff_id INTEGER,
          amount REAL,
          date TEXT,
          is_synced INTEGER DEFAULT 0
        )
      ''');
    }
    if (oldVersion < 25) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS staff_leave (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          staff_id INTEGER,
          date TEXT,
          type REAL,
          is_synced INTEGER DEFAULT 0
        )
      ''');
    }
    if (oldVersion < 26) {
      try {
        await db.execute('ALTER TABLE staff ADD COLUMN role TEXT DEFAULT "Staff"');
      } catch (e) {
        debugPrint("Error adding role column: $e");
      }
    }
    if (oldVersion < 27) {
      try { await db.execute('ALTER TABLE items ADD COLUMN is_deleted INTEGER DEFAULT 0'); } catch(_) {}
      try { await db.execute('ALTER TABLE items ADD COLUMN deleted_at TEXT'); } catch(_) {}
      try { await db.execute('ALTER TABLE categories ADD COLUMN is_deleted INTEGER DEFAULT 0'); } catch(_) {}
      try { await db.execute('ALTER TABLE categories ADD COLUMN deleted_at TEXT'); } catch(_) {}
      try { await db.execute('ALTER TABLE staff ADD COLUMN is_deleted INTEGER DEFAULT 0'); } catch(_) {}
      try { await db.execute('ALTER TABLE staff ADD COLUMN deleted_at TEXT'); } catch(_) {}
    }
    if (oldVersion < 28) {
      try { await db.execute('ALTER TABLE items ADD COLUMN purchase_price REAL'); } catch(_) {}
      try { await db.execute('ALTER TABLE items ADD COLUMN transport_cost REAL'); } catch(_) {}
    }
    if (oldVersion < 29) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS recipes (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          product_id INTEGER,
          material_id INTEGER,
          quantity REAL,
          is_synced INTEGER DEFAULT 0
        )
      ''');
    }
    if (oldVersion < 30) {
      // Handled by the check at the start of _onUpgrade
    }
    if (oldVersion < 37) {
      try { await db.execute('ALTER TABLE suppliers ADD COLUMN is_deleted INTEGER DEFAULT 0'); } catch(_) {}
      try { await db.execute('ALTER TABLE suppliers ADD COLUMN deleted_at TEXT'); } catch(_) {}
      try { await db.execute('ALTER TABLE units ADD COLUMN is_deleted INTEGER DEFAULT 0'); } catch(_) {}
      try { await db.execute('ALTER TABLE units ADD COLUMN deleted_at TEXT'); } catch(_) {}
    }
    if (oldVersion < 35) {
      try { await db.execute('ALTER TABLE staff_advance ADD COLUMN status TEXT DEFAULT "pending"'); } catch(_) {}
    }
    if (oldVersion < 36) {
      try { await db.execute('ALTER TABLE staff ADD COLUMN is_login_enabled INTEGER DEFAULT 0'); } catch(_) {}
      try { await db.execute('ALTER TABLE staff ADD COLUMN staff_code TEXT DEFAULT ""'); } catch(_) {}
      try { await db.execute('ALTER TABLE staff ADD COLUMN login_pin TEXT DEFAULT ""'); } catch(_) {}
      try { await db.execute('ALTER TABLE staff ADD COLUMN permissions TEXT DEFAULT "{\\"can_sale\\":true,\\"can_stock\\":false,\\"can_reports\\":false}"'); } catch(_) {}
    }
    if (oldVersion < 38) {
      try { await db.execute('ALTER TABLE purchase_reminders ADD COLUMN is_deleted INTEGER DEFAULT 0'); } catch(_) {}
      try { await db.execute('ALTER TABLE purchase_reminders ADD COLUMN deleted_at TEXT'); } catch(_) {}
    }
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER,
        type TEXT,
        category TEXT,
        description TEXT,
        amount REAL,
        paid_amount REAL DEFAULT 0,
        quantity REAL,
        unit TEXT,
        rate REAL,
        payment_mode TEXT,
        date TEXT,
        is_synced INTEGER DEFAULT 0,
        cash_amount REAL DEFAULT 0,
        upi_amount REAL DEFAULT 0,
        is_deleted INTEGER DEFAULT 0,
        deleted_at TEXT,
        customer_contact TEXT DEFAULT "",
        status TEXT DEFAULT "completed",
        updated_at TEXT,
        license_id TEXT DEFAULT "NONE"
      )
    ''');

    await db.execute('''
      CREATE TABLE items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        category TEXT,
        unit TEXT,
        min_stock REAL,
        current_stock REAL,
        price REAL,
        half_price REAL,
        full_unit TEXT,
        half_unit TEXT,
        full_qty REAL,
        half_qty REAL,
        item_type TEXT DEFAULT "selling",
        is_synced INTEGER DEFAULT 0,
        low_stock_alert INTEGER DEFAULT 1,
        icon TEXT,
        is_deleted INTEGER DEFAULT 0,
        deleted_at TEXT,
        purchase_price REAL,
        transport_cost REAL,
        linked_item_ids TEXT,
        linked_category_ids TEXT,
        updated_at TEXT,
        license_id TEXT DEFAULT "NONE"
      )
    ''');

    await db.execute('''
      CREATE TABLE suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        contact TEXT,
        items_supplied TEXT,
        notes TEXT,
        is_synced INTEGER DEFAULT 0,
        is_deleted INTEGER DEFAULT 0,
        deleted_at TEXT,
        updated_at TEXT,
        license_id TEXT DEFAULT "NONE"
      )
    ''');

    await db.execute('''
      CREATE TABLE staff (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        role TEXT DEFAULT "Staff",
        monthly_salary REAL,
        advance REAL DEFAULT 0,
        join_date TEXT,
        contact TEXT,
        total_leaves REAL DEFAULT 0,
        image_path TEXT,
        image_url TEXT,
        is_synced INTEGER DEFAULT 0,
        is_deleted INTEGER DEFAULT 0,
        deleted_at TEXT,
        updated_at TEXT,
        license_id TEXT DEFAULT "NONE"
      )
    ''');

    await db.execute('''
      CREATE TABLE staff_advance (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        staff_id INTEGER,
        amount REAL,
        date TEXT,
        status TEXT DEFAULT "pending",
        is_synced INTEGER DEFAULT 0,
        updated_at TEXT,
        license_id TEXT DEFAULT "NONE"
      )
    ''');

    await db.execute('''
      CREATE TABLE staff_leave (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        staff_id INTEGER,
        date TEXT,
        type REAL,
        is_synced INTEGER DEFAULT 0,
        updated_at TEXT,
        license_id TEXT DEFAULT "NONE"
      )
    ''');

    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        icon_name TEXT,
        type TEXT DEFAULT "selling",
        is_synced INTEGER DEFAULT 0,
        display_order INTEGER DEFAULT 0,
        use_category_stock INTEGER DEFAULT 0,
        stock_qty REAL DEFAULT 0,
        low_stock_limit REAL DEFAULT 10,
        is_deleted INTEGER DEFAULT 0,
        deleted_at TEXT,
        updated_at TEXT,
        license_id TEXT DEFAULT "NONE"
      )
    ''');

    await db.execute('''
      CREATE TABLE units (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        is_synced INTEGER DEFAULT 0,
        is_deleted INTEGER DEFAULT 0,
        deleted_at TEXT,
        updated_at TEXT,
        license_id TEXT DEFAULT "NONE"
      )
    ''');

    await db.execute('''
      CREATE TABLE purchase_reminders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER,
        item_name TEXT,
        category TEXT,
        quantity REAL,
        expected_price REAL,
        note TEXT,
        priority TEXT,
        due_date TEXT,
        status TEXT,
        is_synced INTEGER DEFAULT 0,
        is_deleted INTEGER DEFAULT 0,
        deleted_at TEXT,
        updated_at TEXT,
        license_id TEXT DEFAULT "NONE"
      )
    ''');

    await db.execute('''
      CREATE TABLE recipes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER,
        material_id INTEGER,
        quantity REAL,
        is_synced INTEGER DEFAULT 0,
        updated_at TEXT,
        license_id TEXT DEFAULT "NONE"
      )
    ''');
  }

  Future<void> clearAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('transactions');
      await txn.delete('items');
      await txn.delete('categories');
      await txn.delete('staff');
      await txn.delete('staff_advance');
      await txn.delete('staff_leave');
      await txn.delete('suppliers');
      await txn.delete('units');
      await txn.delete('purchase_reminders');
      await txn.delete('recipes');
    });
  }

  Future<int> batchInsert(String table, List<Map<String, dynamic>> dataList) async {
    if (dataList.isEmpty) return 0;
    final db = await instance.database;

    // Self-healing: Ensure columns exist before batch insert
    final firstEntry = dataList.first;
    for (var columnName in firstEntry.keys) {
      // Basic type inference for column creation
      String columnType = 'TEXT';
      if (firstEntry[columnName] is int) columnType = 'INTEGER DEFAULT 0';
      if (firstEntry[columnName] is double) columnType = 'REAL DEFAULT 0';
      
      await _ensureTableColumn(db, table, columnName, columnType);
    }

    await db.transaction((txn) async {
      final batch = txn.batch();
      for (var data in dataList) {
        batch.insert(table, data, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
    return dataList.length;
  }

  /// Implementation of "Last Write Wins" (LWW) for Delta Sync.
  /// Overwrites local data ONLY if cloud's updated_at is newer.
  Future<void> smartMerge(String table, List<Map<String, dynamic>> dataList) async {
    if (dataList.isEmpty) return;
    final db = await instance.database;

    // Self-healing: Ensure columns exist before merge
    final firstEntry = dataList.first;
    for (var columnName in firstEntry.keys) {
      String columnType = 'TEXT';
      if (firstEntry[columnName] is int) columnType = 'INTEGER DEFAULT 0';
      if (firstEntry[columnName] is double) columnType = 'REAL DEFAULT 0';
      
      await _ensureTableColumn(db, table, columnName, columnType);
    }
    
    await db.transaction((txn) async {
      for (var cloudMap in dataList) {
        final id = cloudMap['id'];
        if (id == null) continue;

        final localRecords = await txn.query(table, where: 'id = ?', whereArgs: [id], limit: 1);
        
        if (localRecords.isEmpty) {
          // New record from cloud
          await txn.insert(table, cloudMap, conflictAlgorithm: ConflictAlgorithm.replace);
        } else {
          final localMap = localRecords.first;
          final cloudUpdatedAtStr = cloudMap['updated_at']?.toString();
          final localUpdatedAtStr = localMap['updated_at']?.toString();

          if (cloudUpdatedAtStr != null && localUpdatedAtStr != null) {
            final cloudTime = DateTime.tryParse(cloudUpdatedAtStr);
            final localTime = DateTime.tryParse(localUpdatedAtStr);

            if (cloudTime != null && localTime != null) {
              if (cloudTime.isAfter(localTime)) {
                // Cloud is newer -> Update local
                await txn.update(table, cloudMap, where: 'id = ?', whereArgs: [id]);
              } else if (cloudTime.isAtSameMomentAs(localTime)) {
                // Same time, just ensure synced flag is correct if it came from cloud
                if (localMap['is_synced'] == 0) {
                   await txn.update(table, {'is_synced': 1}, where: 'id = ?', whereArgs: [id]);
                }
              }
              // If local is newer, we do nothing; the local change will be pushed to cloud in the next push cycle.
            }
          } else {
            // Fallback: if no timestamps, cloud wins (assuming it's the backup)
            await txn.update(table, cloudMap, where: 'id = ?', whereArgs: [id]);
          }
        }
      }
    });
  }

  Future<int> updateSyncStatus(String table, int id, int status) async {
    final db = await instance.database;
    return await db.update(table, {'is_synced': status}, where: 'id = ?', whereArgs: [id]);
  }

  Future<List<Map<String, dynamic>>> getUnsyncedData(String table) async {
    final db = await instance.database;
    return await db.query(table, where: 'is_synced = ?', whereArgs: [0]);
  }

  Future<int> insertTransaction(TransactionModel tx) async {
    final db = await instance.database;
    tx.updatedAt = DateTime.now();
    final map = tx.toMap();
    map['license_id'] = FirebaseService.activeLicenseKey ?? 'NONE';
    return await db.insert('transactions', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> insertRecipe(int productId, int materialId, double quantity, {int? isSynced}) async {
    final db = await instance.database;
    return await db.insert('recipes', {
      'product_id': productId,
      'material_id': materialId,
      'quantity': quantity,
      'is_synced': isSynced ?? 0,
      'license_id': FirebaseService.activeLicenseKey ?? 'NONE',
    });
  }

  Future<List<Map<String, dynamic>>> getRecipesByProduct(int productId) async {
    final db = await instance.database;
    return await db.query('recipes', where: 'product_id = ?', whereArgs: [productId]);
  }

  Future<int> deleteRecipesByProduct(int productId) async {
    final db = await instance.database;
    return await db.delete('recipes', where: 'product_id = ?', whereArgs: [productId]);
  }
  Future<int> updateTransaction(TransactionModel tx) async {
    final db = await instance.database;
    tx.updatedAt = DateTime.now();
    tx.isSynced = 0;
    return await db.update('transactions', tx.toMap(), where: 'id = ?', whereArgs: [tx.id]);
  }
  Future<int> softDeleteTransaction(int id) async {
    final db = await instance.database;
    final now = DateTime.now().toIso8601String();
    return await db.update('transactions', {'is_deleted': 1, 'deleted_at': now, 'updated_at': now, 'is_synced': 0}, where: 'id = ?', whereArgs: [id]);
  }
  Future<int> restoreTransaction(int id) async {
    final db = await instance.database;
    final now = DateTime.now().toIso8601String();
    return await db.update('transactions', {'is_deleted': 0, 'deleted_at': null, 'updated_at': now, 'is_synced': 0}, where: 'id = ?', whereArgs: [id]);
  }
  Future<int> permanentDeleteTransaction(int id) async {
    final db = await instance.database;
    return await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }
  Future<List<TransactionModel>> getAllTransactions() async {
    final db = await instance.database;
    final licenseId = FirebaseService.activeLicenseKey ?? 'NONE';
    final result = await db.query('transactions', where: 'license_id = ?', whereArgs: [licenseId], orderBy: 'date DESC');
    return result.map((json) => TransactionModel.fromMap(json)).toList();
  }
  Future<List<TransactionModel>> getUnsyncedTransactions() async {
    final db = await instance.database;
    final licenseId = FirebaseService.activeLicenseKey ?? 'NONE';
    final result = await db.query('transactions', where: 'is_synced = ? AND license_id = ?', whereArgs: [0, licenseId]);
    return result.map((json) => TransactionModel.fromMap(json)).toList();
  }
  Future<int> updateTransactionSyncStatus(int id, int status) async {
    return await updateSyncStatus('transactions', id, status);
  }

  Future<int> insertItem(ItemModel item) async {
    final db = await instance.database;
    try {
      debugPrint("DB: Inserting item: ${item.name} (ID: ${item.id})");
      item.updatedAt = DateTime.now();
      final map = item.toMap();
      map['license_id'] = FirebaseService.activeLicenseKey ?? 'NONE';
      
      // Self-healing for single insert
      for (var col in map.keys) {
         if (col == 'id') continue;
         String type = 'TEXT';
         if (map[col] is int) type = 'INTEGER DEFAULT 0';
         if (map[col] is double) type = 'REAL DEFAULT 0';
         await _ensureTableColumn(db, 'items', col, type);
      }

      return await db.insert('items', map, conflictAlgorithm: ConflictAlgorithm.replace);
    } catch (e) {
      debugPrint("DB ERROR: Failed to insert item ${item.name}: $e");
      return -1;
    }
  }
  
  static String lastRestoreError = "";
  static int lastRestoreSuccessCount = 0;
  static int lastRestoreFailCount = 0;

  Future<void> safeRestoreItems(List<Map<String, dynamic>> itemsFromFirebase) async {
    lastRestoreError = "";
    lastRestoreSuccessCount = 0;
    lastRestoreFailCount = 0;

    debugPrint("RESTORE: Starting restore for ${itemsFromFirebase.length} items");
    
    for (var itemMap in itemsFromFirebase) {
      try {
        final item = ItemModel.fromMap(itemMap);
        await insertItem(item);
        lastRestoreSuccessCount++;
      } catch (e) {
        lastRestoreFailCount++;
        lastRestoreError = e.toString();
        debugPrint("FAILED ITEM: $itemMap | ERROR: $e");
      }
    }
    
    debugPrint("RESTORE COMPLETE: Success: $lastRestoreSuccessCount, Fail: $lastRestoreFailCount");
  }
  Future<List<ItemModel>> getAllItems() async {
    final db = await instance.database;
    final licenseId = FirebaseService.activeLicenseKey ?? 'NONE';
    final result = await db.query('items', where: 'license_id = ?', whereArgs: [licenseId]);
    return result.map((json) => ItemModel.fromMap(json)).toList();
  }
  Future<int> updateItem(ItemModel item) async {
    final db = await instance.database;
    item.updatedAt = DateTime.now();
    item.isSynced = 0;
    return await db.update('items', item.toMap(), where: 'id = ?', whereArgs: [item.id]);
  }
  Future<int> updateItemStock(int id, double newStock) async {
    final db = await instance.database;
    final now = DateTime.now().toIso8601String();
    return await db.update('items', {'current_stock': newStock, 'updated_at': now, 'is_synced': 0}, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> updateCategoryItemsStock(String categoryName, double newStock) async {
    final db = await instance.database;
    final now = DateTime.now().toIso8601String();
    return await db.update(
      'items',
      {'current_stock': newStock, 'updated_at': now, 'is_synced': 0},
      where: 'category = ?',
      whereArgs: [categoryName],
    );
  }
  Future<int> softDeleteItem(int id) async {
    final db = await instance.database;
    final now = DateTime.now().toIso8601String();
    return await db.update('items', {'is_deleted': 1, 'deleted_at': now, 'updated_at': now, 'is_synced': 0}, where: 'id = ?', whereArgs: [id]);
  }
  Future<int> restoreItem(int id) async {
    final db = await instance.database;
    final now = DateTime.now().toIso8601String();
    return await db.update('items', {'is_deleted': 0, 'deleted_at': null, 'updated_at': now, 'is_synced': 0}, where: 'id = ?', whereArgs: [id]);
  }
  Future<int> permanentDeleteItem(int id) async {
    final db = await instance.database;
    return await db.delete('items', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertCategory(CategoryModel category) async {
    final db = await instance.database;
    final map = category.toMap();
    map['license_id'] = FirebaseService.activeLicenseKey ?? 'NONE';

    // Self-healing for categories
    for (var col in map.keys) {
      if (col == 'id') continue;
      String type = 'TEXT';
      if (map[col] is int) type = 'INTEGER DEFAULT 0';
      if (map[col] is double) type = 'REAL DEFAULT 0';
      await _ensureTableColumn(db, 'categories', col, type);
    }

    return await db.insert('categories', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<List<CategoryModel>> getAllCategories() async {
    final db = await instance.database;
    final licenseId = FirebaseService.activeLicenseKey ?? 'NONE';
    final result = await db.query('categories', where: 'license_id = ?', whereArgs: [licenseId], orderBy: 'display_order ASC');
    return result.map((json) => CategoryModel.fromMap(json)).toList();
  }
  Future<int> updateCategory(CategoryModel category) async {
    final db = await instance.database;
    return await db.update('categories', category.toMap(), where: 'id = ?', whereArgs: [category.id]);
  }
  Future<int> updateCategoryStock(int id, double newStock) async {
    final db = await instance.database;
    return await db.update('categories', {'stock_qty': newStock, 'is_synced': 0}, where: 'id = ?', whereArgs: [id]);
  }
  Future<int> softDeleteCategory(int id) async {
    final db = await instance.database;
    return await db.update('categories', {'is_deleted': 1, 'deleted_at': DateTime.now().toIso8601String(), 'is_synced': 0}, where: 'id = ?', whereArgs: [id]);
  }
  Future<int> restoreCategory(int id) async {
    final db = await instance.database;
    return await db.update('categories', {'is_deleted': 0, 'deleted_at': null, 'is_synced': 0}, where: 'id = ?', whereArgs: [id]);
  }
  Future<int> permanentDeleteCategory(int id) async {
    final db = await instance.database;
    return await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertStaff(StaffModel staff) async {
    final db = await instance.database;
    final map = staff.toMap();
    map['license_id'] = FirebaseService.activeLicenseKey ?? 'NONE';
    
    // Self-healing for staff
    for (var col in map.keys) {
      if (col == 'id') continue;
      String type = 'TEXT';
      if (map[col] is int) type = 'INTEGER DEFAULT 0';
      if (map[col] is double) type = 'REAL DEFAULT 0';
      await _ensureTableColumn(db, 'staff', col, type);
    }
    
    return await db.insert('staff', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<List<StaffModel>> getAllStaff() async {
    final db = await instance.database;
    final licenseId = FirebaseService.activeLicenseKey ?? 'NONE';
    final result = await db.query('staff', where: 'license_id = ?', whereArgs: [licenseId]);
    return result.map((json) => StaffModel.fromMap(json)).toList();
  }
  Future<int> updateStaff(StaffModel staff) async {
    final db = await instance.database;
    return await db.update('staff', staff.toMap(), where: 'id = ?', whereArgs: [staff.id]);
  }
  Future<int> softDeleteStaff(int id) async {
    final db = await instance.database;
    return await db.update('staff', {'is_deleted': 1, 'deleted_at': DateTime.now().toIso8601String(), 'is_synced': 0}, where: 'id = ?', whereArgs: [id]);
  }
  Future<int> restoreStaff(int id) async {
    final db = await instance.database;
    return await db.update('staff', {'is_deleted': 0, 'deleted_at': null, 'is_synced': 0}, where: 'id = ?', whereArgs: [id]);
  }
  Future<int> permanentDeleteStaff(int id) async {
    final db = await instance.database;
    return await db.delete('staff', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertSupplier(SupplierModel supplier) async {
    final db = await instance.database;
    final map = supplier.toMap();
    map['license_id'] = FirebaseService.activeLicenseKey ?? 'NONE';
    
    // Self-healing for suppliers
    for (var col in map.keys) {
      if (col == 'id') continue;
      String type = 'TEXT';
      if (map[col] is int) type = 'INTEGER DEFAULT 0';
      if (map[col] is double) type = 'REAL DEFAULT 0';
      await _ensureTableColumn(db, 'suppliers', col, type);
    }

    return await db.insert('suppliers', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<List<SupplierModel>> getAllSuppliers() async {
    final db = await instance.database;
    final licenseId = FirebaseService.activeLicenseKey ?? 'NONE';
    final result = await db.query('suppliers', where: 'license_id = ?', whereArgs: [licenseId]);
    return result.map((json) => SupplierModel.fromMap(json)).toList();
  }
  Future<int> updateSupplier(SupplierModel supplier) async {
    final db = await instance.database;
    return await db.update('suppliers', supplier.toMap(), where: 'id = ?', whereArgs: [supplier.id]);
  }
  Future<int> softDeleteSupplier(int id) async {
    final db = await instance.database;
    final now = DateTime.now().toIso8601String();
    return await db.update('suppliers', {'is_deleted': 1, 'deleted_at': now, 'updated_at': now, 'is_synced': 0}, where: 'id = ?', whereArgs: [id]);
  }
  Future<int> restoreSupplier(int id) async {
    final db = await instance.database;
    final now = DateTime.now().toIso8601String();
    return await db.update('suppliers', {'is_deleted': 0, 'deleted_at': null, 'updated_at': now, 'is_synced': 0}, where: 'id = ?', whereArgs: [id]);
  }
  Future<int> permanentDeleteSupplier(int id) async {
    final db = await instance.database;
    return await db.delete('suppliers', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertUnit(String name, {int? id, int isSynced = 0}) async {
    final db = await instance.database;
    final now = DateTime.now().toIso8601String();
    return await db.insert(
      'units', 
      {
        'id': id,
        'name': name, 
        'is_synced': isSynced,
        'is_deleted': 0,
        'updated_at': now,
        'license_id': FirebaseService.activeLicenseKey ?? 'NONE',
      }, 
      conflictAlgorithm: ConflictAlgorithm.replace
    );
  }

  Future<int> updateUnit(int id, String name) async {
    final db = await instance.database;
    final now = DateTime.now().toIso8601String();
    return await db.update(
      'units',
      {
        'name': name,
        'is_synced': 0,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }
  Future<List<Map<String, dynamic>>> getAllUnits() async {
    final db = await instance.database;
    final licenseId = FirebaseService.activeLicenseKey ?? 'NONE';
    return await db.query('units', where: 'license_id = ?', whereArgs: [licenseId]);
  }
  Future<int> softDeleteUnit(int id) async {
    final db = await instance.database;
    final now = DateTime.now().toIso8601String();
    return await db.update('units', {'is_deleted': 1, 'deleted_at': now, 'updated_at': now, 'is_synced': 0}, where: 'id = ?', whereArgs: [id]);
  }
  Future<int> restoreUnit(int id) async {
    final db = await instance.database;
    final now = DateTime.now().toIso8601String();
    return await db.update('units', {'is_deleted': 0, 'deleted_at': null, 'updated_at': now, 'is_synced': 0}, where: 'id = ?', whereArgs: [id]);
  }
  Future<int> permanentDeleteUnit(int id) async {
    final db = await instance.database;
    return await db.delete('units', where: 'id = ?', whereArgs: [id]);
  }

  // Purchase Reminders
  Future<int> insertPurchaseReminder(PurchaseReminderModel reminder) async {
    final db = await instance.database;
    reminder.updatedAt = DateTime.now();
    reminder.isSynced = 0;
    final map = reminder.toMap();
    map['license_id'] = FirebaseService.activeLicenseKey ?? 'NONE';
    
    // Self-healing for purchase_reminders
    for (var col in map.keys) {
      if (col == 'id') continue;
      String type = 'TEXT';
      if (map[col] is int) type = 'INTEGER DEFAULT 0';
      if (map[col] is double) type = 'REAL DEFAULT 0';
      await _ensureTableColumn(db, 'purchase_reminders', col, type);
    }

    return await db.insert('purchase_reminders', map, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<int> updatePurchaseReminder(PurchaseReminderModel reminder) async {
    final db = await instance.database;
    reminder.updatedAt = DateTime.now();
    reminder.isSynced = 0;
    return await db.update('purchase_reminders', reminder.toMap(), where: 'id = ?', whereArgs: [reminder.id]);
  }

  Future<int> softDeletePurchaseReminder(int id) async {
    final db = await instance.database;
    final now = DateTime.now().toIso8601String();
    return await db.update('purchase_reminders', {
      'is_deleted': 1, 
      'deleted_at': now, 
      'updated_at': now, 
      'is_synced': 0
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> restorePurchaseReminder(int id) async {
    final db = await instance.database;
    final now = DateTime.now().toIso8601String();
    return await db.update('purchase_reminders', {
      'is_deleted': 0, 
      'deleted_at': null, 
      'updated_at': now, 
      'is_synced': 0
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> permanentDeletePurchaseReminder(int id) async {
    final db = await instance.database;
    return await db.delete('purchase_reminders', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<PurchaseReminderModel>> getAllPurchaseReminders() async {
    final db = await instance.database;
    final licenseId = FirebaseService.activeLicenseKey ?? 'NONE';
    final result = await db.query('purchase_reminders', where: 'is_deleted = 0 AND license_id = ?', whereArgs: [licenseId], orderBy: 'due_date ASC');
    return result.map((json) => PurchaseReminderModel.fromMap(json)).toList();
  }
}
