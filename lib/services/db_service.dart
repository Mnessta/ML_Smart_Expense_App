import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/expense_model.dart';
import '../models/budget_model.dart';
import '../services/auth_service.dart';

class DbService {
  static final DbService _instance = DbService._internal();
  factory DbService() => _instance;
  DbService._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final String dbPath = await getDatabasesPath();
    final String path = p.join(dbPath, 'ml_smart_expense.db');
    _db = await openDatabase(
      path,
      version: 5,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE expenses (
            id TEXT PRIMARY KEY,
            remote_id TEXT,
            user_id TEXT,
            amount REAL NOT NULL,
            category TEXT NOT NULL,
            date INTEGER NOT NULL,
            created_at TEXT,
            updated_at TEXT,
            note TEXT,
            paymentMethod TEXT,
            isSynced INTEGER DEFAULT 0,
            type TEXT DEFAULT 'expense'
          );
        ''');
        await db.execute('''
          CREATE TABLE budgets (
            id TEXT PRIMARY KEY,
            category TEXT NOT NULL,
            month INTEGER NOT NULL,
            year INTEGER NOT NULL,
            "limit" REAL NOT NULL,
            spent REAL DEFAULT 0
          );
        ''');
        // Create indexes for better query performance
        await db.execute('CREATE INDEX idx_expenses_date ON expenses(date)');
        await db.execute('CREATE INDEX idx_expenses_category ON expenses(category)');
        await db.execute('CREATE INDEX idx_expenses_type ON expenses(type)');
        await db.execute('CREATE INDEX idx_budgets_month_year ON budgets(month, year)');
      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        if (oldVersion < 2) {
          // Add type column to existing expenses table
          try {
            await db.execute('ALTER TABLE expenses ADD COLUMN type TEXT DEFAULT "expense"');
          } catch (_) {
            // Column might already exist, ignore
          }
        }
        if (oldVersion < 3) {
          // Fix limit column name by recreating table
          try {
            await db.execute('ALTER TABLE budgets RENAME TO budgets_old');
            await db.execute('''
              CREATE TABLE budgets (
                id TEXT PRIMARY KEY,
                category TEXT NOT NULL,
                month INTEGER NOT NULL,
                year INTEGER NOT NULL,
                "limit" REAL NOT NULL,
                spent REAL DEFAULT 0
              );
            ''');
            await db.execute('''
              INSERT INTO budgets (id, category, month, year, "limit", spent)
              SELECT id, category, month, year, "limit", spent FROM budgets_old
            ''');
            await db.execute('DROP TABLE budgets_old');
          } catch (_) {
            // Migration might fail if table structure is different, ignore
          }
        }
        if (oldVersion < 4) {
          // Add indexes for performance
          try {
            await db.execute('CREATE INDEX IF NOT EXISTS idx_expenses_date ON expenses(date)');
            await db.execute('CREATE INDEX IF NOT EXISTS idx_expenses_category ON expenses(category)');
            await db.execute('CREATE INDEX IF NOT EXISTS idx_expenses_type ON expenses(type)');
            await db.execute('CREATE INDEX IF NOT EXISTS idx_budgets_month_year ON budgets(month, year)');
          } catch (_) {
            // Indexes might already exist, ignore
          }
        }
        if (oldVersion < 5) {
          // Add sync fields for Supabase integration
          try {
            await db.execute('ALTER TABLE expenses ADD COLUMN remote_id TEXT');
            await db.execute('ALTER TABLE expenses ADD COLUMN user_id TEXT');
            await db.execute('ALTER TABLE expenses ADD COLUMN created_at TEXT');
            await db.execute('ALTER TABLE expenses ADD COLUMN updated_at TEXT');
            await db.execute('CREATE INDEX IF NOT EXISTS idx_expenses_remote_id ON expenses(remote_id)');
            await db.execute('CREATE INDEX IF NOT EXISTS idx_expenses_user_id ON expenses(user_id)');
            await db.execute('CREATE INDEX IF NOT EXISTS idx_expenses_synced ON expenses(isSynced)');
          } catch (_) {
            // Columns might already exist, ignore
          }
        }
      },
    );
    return _db!;
  }

  // Expenses CRUD
  Future<void> upsertExpense(ExpenseModel expense, {String? userId}) async {
    final Database db = await database;
    final Map<String, dynamic> expenseMap = expense.toMap();
    
    // Determine user_id based on current context
    String? finalUserId = userId;
    if (finalUserId == null) {
      // Auto-detect user_id from current context
      if (AuthService().isLoggedIn) {
        finalUserId = AuthService().currentUserId;
      } else {
        // Guest mode - explicitly set to null
        final SharedPreferences prefs = await SharedPreferences.getInstance();
        final bool isGuestMode = prefs.getBool('isGuestMode') ?? false;
        finalUserId = isGuestMode ? null : AuthService().currentUserId;
      }
    }
    
    // Set user_id (null for guest mode, actual ID for logged-in users)
    expenseMap['user_id'] = finalUserId;
    
    // Logged-in user - add sync fields
    if (expenseMap['created_at'] == null) {
      expenseMap['created_at'] = expense.date.toIso8601String();
    }
    if (expenseMap['updated_at'] == null) {
      expenseMap['updated_at'] = DateTime.now().toIso8601String();
    }
    // Mark as unsynced if it's a new expense
    if (expense.isSynced == false) {
      expenseMap['isSynced'] = 0;
    }
      
    await db.insert('expenses', expenseMap, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Get the current user ID for filtering (null for guest mode)
  Future<String?> _getCurrentUserId() async {
    if (AuthService().isLoggedIn) {
      return AuthService().currentUserId;
    }
    // For guest mode, return null - guest expenses have user_id = null
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final bool isGuestMode = prefs.getBool('isGuestMode') ?? false;
    return isGuestMode ? null : AuthService().currentUserId;
  }

  Future<List<ExpenseModel>> getExpenses({String? category, int? fromMs, int? toMs}) async {
    final Database db = await database;
    final String? currentUserId = await _getCurrentUserId();
    
    final List<String> whereParts = <String>[];
    final List<Object?> whereArgs = <Object?>[];
    
    // CRITICAL: Filter by user_id to separate guest and logged-in user data
    if (currentUserId != null) {
      // Logged-in user - only show their expenses
      whereParts.add('user_id = ?');
      whereArgs.add(currentUserId);
    } else {
      // Guest mode - only show expenses with null user_id
      whereParts.add('(user_id IS NULL OR user_id = "")');
    }
    
    if (category != null) {
      whereParts.add('category = ?');
      whereArgs.add(category);
    }
    if (fromMs != null) {
      whereParts.add('date >= ?');
      whereArgs.add(fromMs);
    }
    if (toMs != null) {
      whereParts.add('date <= ?');
      whereArgs.add(toMs);
    }
    
    final String where = whereParts.join(' AND ');
    final List<Map<String, Object?>> rows = await db.query(
      'expenses',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'date DESC',
    );
    return rows.map((Map<String, Object?> m) => ExpenseModel.fromMap(m as Map<String, dynamic>)).toList();
  }

  Future<ExpenseModel?> getExpenseById(String id) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'expenses',
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return ExpenseModel.fromMap(rows.first as Map<String, dynamic>);
  }

  Future<void> deleteExpense(String id, {bool syncDelete = true}) async {
    final Database db = await database;
    await db.delete('expenses', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<String?> getExpenseRemoteId(String localId) async {
    final Database db = await database;
    final List<Map<String, Object?>> rows = await db.query(
      'expenses',
      columns: ['remote_id'],
      where: 'id = ?',
      whereArgs: <Object?>[localId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      return rows.first['remote_id']?.toString();
    }
    return null;
  }

  Future<void> markExpenseSynced(String id, {String? remoteId}) async {
    final Database db = await database;
    final Map<String, Object?> updates = <String, Object?>{'isSynced': 1};
    if (remoteId != null) {
      updates['remote_id'] = remoteId;
    }
    await db.update('expenses', updates, where: 'id = ?', whereArgs: <Object?>[id]);
  }

  Future<void> markExpenseSyncedByRemoteId(String remoteId) async {
    final Database db = await database;
    await db.update('expenses', <String, Object?>{'isSynced': 1}, where: 'remote_id = ?', whereArgs: <Object?>[remoteId]);
  }

  Future<List<ExpenseModel>> getUnsyncedExpenses() async {
    final Database db = await database;
    // Only get unsynced expenses for logged-in users (not guest mode)
    final String? currentUserId = await _getCurrentUserId();
    if (currentUserId == null) {
      // Guest mode - no unsynced expenses (they don't sync)
      return <ExpenseModel>[];
    }
    final List<Map<String, Object?>> rows = await db.query(
      'expenses',
      where: 'isSynced = 0 AND user_id = ?',
      whereArgs: [currentUserId],
    );
    return rows.map((Map<String, Object?> m) => ExpenseModel.fromMap(m as Map<String, dynamic>)).toList();
  }

  // Get expenses as raw maps for sync (includes all fields)
  Future<List<Map<String, dynamic>>> getUnsyncedExpensesRaw() async {
    final Database db = await database;
    // Only get unsynced expenses for logged-in users (not guest mode)
    final String? currentUserId = await _getCurrentUserId();
    if (currentUserId == null) {
      // Guest mode - no unsynced expenses
      return <Map<String, dynamic>>[];
    }
    final List<Map<String, Object?>> rows = await db.query(
      'expenses',
      where: 'isSynced = 0 AND user_id = ?',
      whereArgs: [currentUserId],
    );
    return rows.map((Map<String, Object?> row) {
      final Map<String, dynamic> result = <String, dynamic>{};
      row.forEach((key, value) {
        result[key] = value;
      });
      return result;
    }).toList();
  }

  // Update expense with remote data
  Future<void> updateExpenseFromRemote(Map<String, dynamic> remoteData) async {
    final Database db = await database;
    final String? remoteId = remoteData['id']?.toString();
    if (remoteId == null) return;
    
    // Check if exists by remote_id
    final List<Map<String, Object?>> existing = await db.query(
      'expenses',
      where: 'remote_id = ?',
      whereArgs: [remoteId],
      limit: 1,
    );

    // Preserve or derive correct transaction type:
    // 1. Prefer remote "type" field if present.
    // 2. Otherwise, keep existing local type if we already have a record.
    // 3. Fallback to "expense" only when we truly don't know (new record, no type info).
    String resolvedType = 'expense';
    final String? remoteType = remoteData['type']?.toString();
    if (remoteType == 'income' || remoteType == 'expense') {
      resolvedType = remoteType!;
    } else if (existing.isNotEmpty) {
      final Object? existingType = existing.first['type'];
      if (existingType == 'income' || existingType == 'expense') {
        resolvedType = existingType as String;
      }
    }

    final Map<String, Object?> expenseData = <String, Object?>{
      'remote_id': remoteId,
      'user_id': remoteData['user_id']?.toString(),
      'amount': remoteData['amount'],
      'category': remoteData['category'] as String?,
      'note': remoteData['note'] as String?,
      'paymentMethod': remoteData['payment'] as String? ?? 'Cash',
      'created_at': remoteData['created_at']?.toString(),
      'updated_at': remoteData['updated_at']?.toString() ?? remoteData['created_at']?.toString(),
      'isSynced': 1,
      'type': resolvedType,
    };

    // Convert created_at to date (INTEGER) if needed
    if (remoteData['created_at'] != null) {
      try {
        final DateTime dateTime = DateTime.parse(remoteData['created_at'].toString());
        expenseData['date'] = dateTime.millisecondsSinceEpoch;
      } catch (_) {
        // If parsing fails, use current time
        expenseData['date'] = DateTime.now().millisecondsSinceEpoch;
      }
    }

    if (existing.isNotEmpty) {
      // Update existing
      await db.update('expenses', expenseData, where: 'remote_id = ?', whereArgs: [remoteId]);
    } else {
      // Insert new
      expenseData['id'] = remoteId; // Use remote_id as local id too
      await db.insert('expenses', expenseData, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  // Budgets CRUD
  Future<void> upsertBudget(BudgetModel budget) async {
    final Database db = await database;
    await db.insert('budgets', budget.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<BudgetModel>> getBudgets({int? month, int? year}) async {
    final Database db = await database;
    String? where;
    List<Object?>? args;
    if (month != null && year != null) {
      where = 'month = ? AND year = ?';
      args = <Object?>[month, year];
    }
    final List<Map<String, Object?>> rows = await db.query('budgets', where: where, whereArgs: args);
    final List<BudgetModel> budgets = rows.map((Map<String, Object?> m) => BudgetModel.fromMap(m as Map<String, dynamic>)).toList();
    
    // Calculate spent amounts from expenses
    final DateTime now = DateTime.now();
    final int targetMonth = month ?? now.month;
    final int targetYear = year ?? now.year;
    final DateTime startOfMonth = DateTime(targetYear, targetMonth, 1);
    final DateTime endOfMonth = DateTime(targetYear, targetMonth + 1, 0, 23, 59, 59);
    
    final List<ExpenseModel> monthExpenses = await getExpenses(
      fromMs: startOfMonth.millisecondsSinceEpoch,
      toMs: endOfMonth.millisecondsSinceEpoch,
    );
    
    // Update spent amounts for each budget
    final List<BudgetModel> updatedBudgets = <BudgetModel>[];
    for (final BudgetModel budget in budgets) {
      final double spent = monthExpenses
          .where((ExpenseModel e) => e.category == budget.category)
          .fold(0.0, (double sum, ExpenseModel e) => sum + e.amount);
      
      final BudgetModel updatedBudget = BudgetModel(
        id: budget.id,
        category: budget.category,
        month: budget.month,
        year: budget.year,
        limit: budget.limit,
        spent: spent,
      );
      
      if (spent != budget.spent) {
        await upsertBudget(updatedBudget);
      }
      
      updatedBudgets.add(updatedBudget);
    }
    
    return updatedBudgets;
  }

  Future<void> deleteBudget(String id) async {
    final Database db = await database;
    await db.delete('budgets', where: 'id = ?', whereArgs: <Object?>[id]);
  }

  /// Clear all guest mode data (expenses with user_id = null)
  /// Called when user logs in to clean up guest data
  Future<void> clearGuestData() async {
    final Database db = await database;
    // Delete all expenses with null or empty user_id (guest mode data)
    await db.delete('expenses', where: 'user_id IS NULL OR user_id = ""');
    // Note: Budgets don't have user_id column yet, so we'll handle them separately
    // For now, budgets are shared - we may want to add user_id to budgets later
  }

  /// Delete all expenses for a specific user
  Future<void> deleteUserExpenses(String userId) async {
    final Database db = await database;
    await db.delete('expenses', where: 'user_id = ?', whereArgs: [userId]);
  }
}


