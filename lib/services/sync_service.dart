import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'db_service.dart';
import '../utils/logger.dart';
import '../utils/supabase_guard.dart';

class SyncService {
  StreamSubscription? _connSub;
  bool _isSyncing = false;

  SupabaseClient? get _supabase {
    if (!isSupabaseInitialized()) return null;
    return Supabase.instance.client;
  }

  void start() {
    final supabase = _supabase;
    if (supabase == null) return;

    // Listen to connectivity changes
    _connSub = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.any((result) => result != ConnectivityResult.none)) {
        _syncToServer();
        _pullFromServer();
      }
    });

    // Set up realtime subscription for expenses table
    supabase.channel('public:expenses')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'expenses',
          callback: (payload) {
            // When server new insert appears — add to local DB if missing
            _handleServerInsert(payload.newRecord);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'expenses',
          callback: (payload) {
            // Handle server updates
            _handleServerUpdate(payload.newRecord);
          },
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'expenses',
          callback: (payload) {
            // Handle server deletes
            _handleServerDelete(payload.oldRecord);
          },
        )
        .subscribe();
  }

  Future<void> _syncToServer() async {
    final supabase = _supabase;
    if (supabase == null) return;

    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final unsynced = await DbService().getUnsyncedExpensesRaw();
      final user = supabase.auth.currentUser;
      if (user == null) {
        _isSyncing = false;
        return;
      }

      for (final rec in unsynced) {
        try {
          // Convert DbService format to Supabase format
          final DateTime dateTime = DateTime.fromMillisecondsSinceEpoch(rec['date'] as int);
          final String createdAt = rec['created_at'] as String? ?? dateTime.toIso8601String();
          
          final res = await supabase.from('expenses').insert({
            'user_id': rec['user_id'] ?? user.id,
            'amount': rec['amount'],
            'category': rec['category'],
            'payment': rec['paymentMethod'] ?? 'Cash', // Map paymentMethod to payment
            'note': rec['note'],
            'created_at': createdAt,
          }).select().single();

          if (res['id'] != null) {
            await DbService().markExpenseSynced(
              rec['id'] as String,
              remoteId: res['id'].toString(),
            );
          }
        } catch (e) {
          // Network/server error — skip, will retry later
          AppLogger.e('Error syncing expense to server', e);
        }
      }
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _pullFromServer() async {
    final supabase = _supabase;
    if (supabase == null) return;

    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final user = supabase.auth.currentUser;
      if (user == null) {
        _isSyncing = false;
        return;
      }

      final data = await supabase.from('expenses')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      for (final row in data) {
        // Use DbService to update/insert from remote
        await DbService().updateExpenseFromRemote(Map<String, dynamic>.from(row));
      }
    } catch (e) {
      AppLogger.e('Error pulling from server', e);
    } finally {
      _isSyncing = false;
    }
  }

  Future<void> _handleServerInsert(Map<String, dynamic> newRow) async {
    try {
      final supabase = _supabase;
      if (supabase == null) return;

      final user = supabase.auth.currentUser;
      
      // Only handle if it's for the current user
      if (user == null || newRow['user_id'] != user.id) return;

      // Use DbService to handle the insert
      await DbService().updateExpenseFromRemote(newRow);
    } catch (e) {
      AppLogger.e('Error handling server insert', e);
    }
  }

  Future<void> _handleServerUpdate(Map<String, dynamic> updatedRow) async {
    try {
      final supabase = _supabase;
      if (supabase == null) return;

      final user = supabase.auth.currentUser;
      
      if (user == null || updatedRow['user_id'] != user.id) return;

      // Use DbService to handle the update
      await DbService().updateExpenseFromRemote(updatedRow);
    } catch (e) {
      AppLogger.e('Error handling server update', e);
    }
  }

  Future<void> _handleServerDelete(Map<String, dynamic> deletedRow) async {
    try {
      final supabase = _supabase;
      if (supabase == null) return;

      final user = supabase.auth.currentUser;
      
      if (user == null || deletedRow['user_id'] != user.id) return;

      // Delete local record by remote_id
      final db = await DbService().database;
      await db.delete(
        'expenses',
        where: 'remote_id = ?',
        whereArgs: [deletedRow['id']?.toString()],
      );
    } catch (e) {
      AppLogger.e('Error handling server delete', e);
    }
  }

  // Manual sync trigger
  Future<void> syncNow() async {
    await _syncToServer();
    await _pullFromServer();
  }

  /// Sync a single expense immediately
  /// Accepts either ExpenseModel or `Map<String, dynamic>`
  Future<void> syncExpense(dynamic expense) async {
    try {
      final supabase = _supabase;
      if (supabase == null) return;

      final user = supabase.auth.currentUser;
      if (user == null) return;

      Map<String, dynamic> expenseData;
      
      // Convert ExpenseModel to map if needed
      if (expense is Map<String, dynamic>) {
        expenseData = expense;
      } else {
        // Assume it's an ExpenseModel-like object with toMap method
        expenseData = expense.toMap();
        // Convert to LocalDB format
        expenseData = {
          'id': expenseData['id'],
          'user_id': user.id,
          'amount': expenseData['amount'],
          'category': expenseData['category'],
          'payment': expenseData['paymentMethod'] ?? 'Cash',
          'note': expenseData['note'],
          'created_at': (expenseData['date'] is int) 
              ? DateTime.fromMillisecondsSinceEpoch(expenseData['date'] as int).toIso8601String()
              : (expenseData['date'] is DateTime)
                  ? (expenseData['date'] as DateTime).toIso8601String()
                  : DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
          'synced': expenseData['isSynced'] == true || expenseData['isSynced'] == 1 ? 1 : 0,
        };
      }

      // Check if already synced
      if (expenseData['synced'] == 1 && expenseData['remote_id'] != null) {
        return; // Already synced
      }

      // Convert ExpenseModel to Supabase format
      final DateTime expenseDate = expenseData['date'] is int
          ? DateTime.fromMillisecondsSinceEpoch(expenseData['date'] as int)
          : (expenseData['date'] is DateTime)
              ? expenseData['date'] as DateTime
              : DateTime.now();

      final res = await supabase.from('expenses').insert({
        'user_id': expenseData['user_id'] ?? user.id,
        'amount': expenseData['amount'],
        'category': expenseData['category'],
        'payment': expenseData['paymentMethod'] ?? expenseData['payment'] ?? 'Cash',
        'note': expenseData['note'],
        'created_at': expenseData['created_at'] is String 
            ? expenseData['created_at']
            : expenseDate.toIso8601String(),
      }).select().single();

      if (res['id'] != null && expenseData['id'] != null) {
        await DbService().markExpenseSynced(
          expenseData['id'] as String,
          remoteId: res['id'].toString(),
        );
      }
    } catch (e) {
      // Sync failed - will retry later
      AppLogger.e('Error syncing expense', e);
    }
  }

  /// Sync a single budget immediately
  /// Accepts either BudgetModel or `Map<String, dynamic>`
  Future<void> syncBudget(dynamic budget) async {
    try {
      final supabase = _supabase;
      if (supabase == null) return;

      final user = supabase.auth.currentUser;
      if (user == null) return;

      Map<String, dynamic> budgetData;
      
      // Convert BudgetModel to map if needed
      if (budget is Map<String, dynamic>) {
        budgetData = budget;
      } else {
        // Assume it's a BudgetModel-like object with toMap method
        budgetData = budget.toMap();
        // Convert month/year to period_start/period_end
        final month = budgetData['month'] as int;
        final year = budgetData['year'] as int;
        final periodStart = DateTime(year, month, 1);
        final periodEnd = DateTime(year, month + 1, 0); // Last day of month
        
        budgetData = {
          'user_id': user.id,
          'category': budgetData['category'],
          'limit_amount': budgetData['limit'] ?? budgetData['limit_amount'],
          'period_start': periodStart.toIso8601String().split('T')[0], // Date only
          'period_end': periodEnd.toIso8601String().split('T')[0], // Date only
        };
      }

      await supabase.from('budgets').insert({
        'user_id': user.id,
        'category': budgetData['category'],
        'limit_amount': budgetData['limit_amount'] ?? budgetData['limit'],
        'period_start': budgetData['period_start'],
        'period_end': budgetData['period_end'],
      });
    } catch (e) {
      // Sync failed - will retry later
      AppLogger.e('Error syncing budget', e);
    }
  }

  /// Delete expense from server
  Future<void> deleteExpenseFromServer(String expenseId, {String? remoteId}) async {
    try {
      final supabase = _supabase;
      if (supabase == null) return;

      final user = supabase.auth.currentUser;
      if (user == null) return;

      // If we have remote_id, delete by that
      if (remoteId != null) {
        await supabase.from('expenses').delete().eq('id', remoteId).eq('user_id', user.id);
      } else {
        // Try to find by local id (if it was synced)
        final db = await DbService().database;
        final List<Map<String, Object?>> rows = await db.query(
          'expenses',
          where: 'id = ?',
          whereArgs: [expenseId],
          limit: 1,
        );
        
        if (rows.isNotEmpty && rows.first['remote_id'] != null) {
          final String? remoteIdFromDb = rows.first['remote_id']?.toString();
          if (remoteIdFromDb != null) {
            await supabase.from('expenses').delete().eq('id', remoteIdFromDb).eq('user_id', user.id);
          }
        }
      }
    } catch (e) {
      AppLogger.e('Error deleting expense from server', e);
      // Don't throw - local delete should still happen
    }
  }

  void dispose() {
    _connSub?.cancel();
    _supabase?.removeAllChannels();
  }
}
