import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../../models/transaction_model.dart';
import '../../models/item_model.dart';
import '../../models/supplier_model.dart';
import '../../models/staff_model.dart';
import '../../models/category_model.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('food_cart.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path, 
      version: 16, // Incremented version for status and staff leave
      onCreate: _createDB, 
      onUpgrade: _onUpgrade
    );
  }

  Future _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 7) {
      await db.execute('ALTER TABLE transactions ADD COLUMN paid_amount REAL DEFAULT 0');
    }
    if (oldVersion < 8) {
      try { await db.execute('ALTER TABLE items ADD COLUMN price REAL'); } catch(_) {}
      try { await db.execute('ALTER TABLE items ADD COLUMN half_price REAL'); } catch(_) {}
      try { await db.execute('ALTER TABLE items ADD COLUMN full_unit TEXT'); } catch(_) {}
      try { await db.execute('ALTER TABLE items ADD COLUMN half_unit TEXT'); } catch(_) {}
    }
    if (oldVersion < 9) {
      try { await db.execute('ALTER TABLE items ADD COLUMN full_qty REAL'); } catch(_) {}
      try { await db.execute('ALTER TABLE items ADD COLUMN half_qty REAL'); } catch(_) {}
    }
    if (oldVersion < 10) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS categories (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT,
          icon_name TEXT
        )
      ''');
    }
    if (oldVersion < 11) {
      try { await db.execute('ALTER TABLE transactions ADD COLUMN cash_amount REAL DEFAULT 0'); } catch(_) {}
      try { await db.execute('ALTER TABLE transactions ADD COLUMN upi_amount REAL DEFAULT 0'); } catch(_) {}
      try { await db.execute('ALTER TABLE transactions ADD COLUMN is_deleted INTEGER DEFAULT 0'); } catch(_) {}
      try { await db.execute('ALTER TABLE transactions ADD COLUMN deleted_at TEXT'); } catch(_) {}
    }
    if (oldVersion < 12) {
      try { await db.execute('ALTER TABLE transactions ADD COLUMN customer_contact TEXT DEFAULT ""'); } catch(_) {}
    }
    if (oldVersion < 13) {
      try { await db.execute('ALTER TABLE items ADD COLUMN item_type TEXT DEFAULT "selling"'); } catch(_) {}
    }
    if (oldVersion < 14) {
      try { await db.execute('ALTER TABLE categories ADD COLUMN type TEXT DEFAULT "selling"'); } catch(_) {}
    }
    if (oldVersion < 15) {
      try { await db.execute('ALTER TABLE transactions ADD COLUMN status TEXT DEFAULT "completed"'); } catch(_) {}
    }
    if (oldVersion < 16) {
      try { await db.execute('ALTER TABLE staff ADD COLUMN total_leaves INTEGER DEFAULT 0'); } catch(_) {}
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
        is_synced INTEGER,
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
        item_type TEXT DEFAULT "selling"
      )
    ''');

    await db.execute('''
      CREATE TABLE suppliers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        contact TEXT,
        items_supplied TEXT,
        notes TEXT
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
        total_leaves INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        icon_name TEXT,
        type TEXT DEFAULT "selling"
      )
    ''');
  }

  // Transaction Methods
  Future<int> insertTransaction(TransactionModel tx) async {
    final db = await instance.database;
    return await db.insert('transactions', tx.toMap());
  }
  Future<int> updateTransaction(TransactionModel tx) async {
    final db = await instance.database;
    return await db.update('transactions', tx.toMap(), where: 'id = ?', whereArgs: [tx.id]);
  }
  
  Future<int> softDeleteTransaction(int id) async {
    final db = await instance.database;
    return await db.update('transactions', {
      'is_deleted': 1,
      'deleted_at': DateTime.now().toIso8601String()
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> restoreTransaction(int id) async {
    final db = await instance.database;
    return await db.update('transactions', {
      'is_deleted': 0,
      'deleted_at': null
    }, where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deleteTransactionPermanently(int id) async {
    final db = await instance.database;
    return await db.delete('transactions', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<TransactionModel>> getAllTransactions() async {
    final db = await instance.database;
    final result = await db.query('transactions', orderBy: 'date DESC');
    return result.map((json) => TransactionModel.fromMap(json)).toList();
  }

  Future<int> updateTransactionSyncStatus(int id, int status) async {
    final db = await instance.database;
    return await db.update('transactions', {'is_synced': status}, where: 'id = ?', whereArgs: [id]);
  }
  Future<List<TransactionModel>> getUnsyncedTransactions() async {
    final db = await instance.database;
    final result = await db.query('transactions', where: 'is_synced = ?', whereArgs: [0]);
    return result.map((json) => TransactionModel.fromMap(json)).toList();
  }

  // Item Methods
  Future<int> insertItem(ItemModel item) async {
    final db = await instance.database;
    return await db.insert('items', item.toMap());
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
    return await db.update('items', {'current_stock': newStock}, where: 'id = ?', whereArgs: [id]);
  }
  Future<int> deleteItem(int id) async {
    final db = await instance.database;
    return await db.delete('items', where: 'id = ?', whereArgs: [id]);
  }

  // Staff Methods
  Future<int> insertStaff(StaffModel staff) async {
    final db = await instance.database;
    return await db.insert('staff', staff.toMap());
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

  // Supplier Methods
  Future<int> insertSupplier(SupplierModel supplier) async {
    final db = await instance.database;
    return await db.insert('suppliers', supplier.toMap());
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
    return await db.delete('categories', where: 'id = ?', whereArgs: [id]);
  }
}
