import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../models/transaction_model.dart';
import '../../models/item_model.dart';
import '../../models/supplier_model.dart';
import '../../models/staff_model.dart';
import '../../models/category_model.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;
  static String? _currentUserId;

  DatabaseHelper._init();

  Future<Database> get database async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception("User not logged in");

    if (_currentUserId != user.uid) {
      await closeDatabase();
      _currentUserId = user.uid;
      _database = await _initDB('food_cart_${user.uid}.db');
    }

    if (_database != null) return _database!;
    _database = await _initDB('food_cart_${user.uid}.db');
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
      version: 23, 
      onCreate: _createDB, 
      onUpgrade: _onUpgrade
    );
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
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
        status TEXT DEFAULT "completed"
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
        icon TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        contact TEXT,
        items_supplied TEXT,
        notes TEXT,
        is_synced INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE staff (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        monthly_salary REAL,
        advance REAL,
        join_date TEXT,
        contact TEXT,
        total_leaves INTEGER DEFAULT 0,
        is_synced INTEGER DEFAULT 0
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
        low_stock_limit REAL DEFAULT 10
      )
    ''');

    await db.execute('''
      CREATE TABLE units (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        is_synced INTEGER DEFAULT 0
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
        is_synced INTEGER DEFAULT 0
      )
    ''');
  }

  Future<void> clearAllData() async {
    final db = await instance.database;
    await db.delete('transactions');
    await db.delete('items');
    await db.delete('categories');
    await db.delete('staff');
    await db.delete('suppliers');
    await db.delete('units');
    await db.delete('purchase_reminders');
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
    return await db.insert('transactions', tx.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<int> updateTransaction(TransactionModel tx) async {
    final db = await instance.database;
    return await db.update('transactions', tx.toMap(), where: 'id = ?', whereArgs: [tx.id]);
  }
  Future<int> softDeleteTransaction(int id) async {
    final db = await instance.database;
    return await db.update('transactions', {'is_deleted': 1, 'deleted_at': DateTime.now().toIso8601String(), 'is_synced': 0}, where: 'id = ?', whereArgs: [id]);
  }
  Future<int> restoreTransaction(int id) async {
    final db = await instance.database;
    return await db.update('transactions', {'is_deleted': 0, 'deleted_at': null, 'is_synced': 0}, where: 'id = ?', whereArgs: [id]);
  }
  Future<int> permanentDeleteTransaction(int id) async {
    final db = await instance.database;
    return await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }
  Future<List<TransactionModel>> getAllTransactions() async {
    final db = await instance.database;
    final result = await db.query('transactions', orderBy: 'date DESC');
    return result.map((json) => TransactionModel.fromMap(json)).toList();
  }
  Future<List<TransactionModel>> getUnsyncedTransactions() async {
    final db = await instance.database;
    final result = await db.query('transactions', where: 'is_synced = ?', whereArgs: [0]);
    return result.map((json) => TransactionModel.fromMap(json)).toList();
  }
  Future<int> updateTransactionSyncStatus(int id, int status) async {
    return await updateSyncStatus('transactions', id, status);
  }

  Future<int> insertItem(ItemModel item) async {
    final db = await instance.database;
    return await db.insert('items', item.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<List<ItemModel>> getAllItems() async {
    final db = await instance.database;
    final result = await db.query('items');
    return result.map((json) => ItemModel.fromMap(json)).toList();
  }
  Future<int> updateItem(ItemModel item) async {
    final db = await instance.database;
    return await db.update('items', item.toMap(), where: 'id = ?', whereArgs: [item.id]);
  }
  Future<int> updateItemStock(int id, double newStock) async {
    final db = await instance.database;
    return await db.update('items', {'current_stock': newStock, 'is_synced': 0}, where: 'id = ?', whereArgs: [id]);
  }
  Future<int> deleteItem(int id) async {
    final db = await instance.database;
    return await db.delete('items', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertCategory(CategoryModel category) async {
    final db = await instance.database;
    return await db.insert('categories', category.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<List<CategoryModel>> getAllCategories() async {
    final db = await instance.database;
    final result = await db.query('categories', orderBy: 'display_order ASC');
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
  Future<int> deleteCategory(int id) async {
    final db = await instance.database;
    return await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertStaff(StaffModel staff) async {
    final db = await instance.database;
    return await db.insert('staff', staff.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<List<StaffModel>> getAllStaff() async {
    final db = await instance.database;
    final result = await db.query('staff');
    return result.map((json) => StaffModel.fromMap(json)).toList();
  }
  Future<int> updateStaff(StaffModel staff) async {
    final db = await instance.database;
    return await db.update('staff', staff.toMap(), where: 'id = ?', whereArgs: [staff.id]);
  }
  Future<int> deleteStaff(int id) async {
    final db = await instance.database;
    return await db.delete('staff', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertSupplier(SupplierModel supplier) async {
    final db = await instance.database;
    return await db.insert('suppliers', supplier.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }
  Future<List<SupplierModel>> getAllSuppliers() async {
    final db = await instance.database;
    final result = await db.query('suppliers');
    return result.map((json) => SupplierModel.fromMap(json)).toList();
  }
  Future<int> updateSupplier(SupplierModel supplier) async {
    final db = await instance.database;
    return await db.update('suppliers', supplier.toMap(), where: 'id = ?', whereArgs: [supplier.id]);
  }
  Future<int> deleteSupplier(int id) async {
    final db = await instance.database;
    return await db.delete('suppliers', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> insertUnit(String name, {int? id, int isSynced = 0}) async {
    final db = await instance.database;
    return await db.insert(
      'units', 
      {
        if (id != null) 'id': id,
        'name': name, 
        'is_synced': isSynced
      }, 
      conflictAlgorithm: ConflictAlgorithm.replace
    );
  }
  Future<List<Map<String, dynamic>>> getAllUnits() async {
    final db = await instance.database;
    return await db.query('units');
  }
  Future<int> deleteUnit(int id) async {
    final db = await instance.database;
    return await db.delete('units', where: 'id = ?', whereArgs: [id]);
  }
}
