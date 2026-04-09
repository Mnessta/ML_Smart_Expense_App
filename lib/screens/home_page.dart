import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:provider/provider.dart';
import '../services/finance_service.dart';
import '../services/db_service.dart';
import '../services/sync_service.dart';
import '../models/categories.dart';
import '../models/expense_model.dart';
import '../widgets/offline_indicator.dart';
import '../providers/connectivity_provider.dart';
import '../providers/currency_provider.dart';
import '../services/auth_service.dart';
import 'add_income_screen.dart';
import 'package:go_router/go_router.dart';
import '../app_router.dart';
import 'budget_screen.dart';
import 'settings_screen.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // Form controllers
  final TextEditingController amountController = TextEditingController();
  final TextEditingController noteController = TextEditingController();

  String selectedCategory = "Food";
  String selectedPayment = "Cash";
  DateTime selectedDate = DateTime.now();

  // Transactions from local DB
  List<Map<String, dynamic>> transactions = [];
  final Uuid _uuid = Uuid();
  bool _isLoading = false;
  bool _isSyncing = false;
  double _totalBalance = 0.0;
  double _totalIncome = 0.0;
  double _totalExpenses = 0.0;
  double _linkedIncome = 0.0;
  int? _activeTransactionIndex;

  // Navigation state
  int _currentIndex = 0;
  int? _hoveredIndex;
  final Map<int, GlobalKey> _menuKeys = {
    0: GlobalKey(),
    1: GlobalKey(),
    2: GlobalKey(),
    3: GlobalKey(),
    4: GlobalKey(),
  };

  @override
  void initState() {
    super.initState();
    _loadLinkedIncome();
    fetchExpenses();
    _calculateBalance();
  }

  Future<void> _loadLinkedIncome() async {
    final double value = await FinanceService.getLinkedIncome();
    if (!mounted) return;
    setState(() {
      _linkedIncome = value;
      _calculateBalance(emitSetState: false);
    });
  }

  Future<void> fetchExpenses() async {
    setState(() => _isLoading = true);
    try {
      final List<ExpenseModel> expenses = await DbService().getExpenses();

      if (mounted) {
        setState(() {
          final seenKeys = <String>{};
          final unique = <Map<String, dynamic>>[];
          for (final ExpenseModel expense in expenses) {
            final key = expense.id;
            if (seenKeys.contains(key)) {
              continue;
            }
            seenKeys.add(key);
            unique.add({
              "id": expense.id,
              "amount": expense.amount,
              "category": expense.category,
              "payment": expense.paymentMethod,
              "note": expense.note ?? '',
              "date": expense.date, // Use the actual date from ExpenseModel with full time precision
            });
          }
          transactions = unique;
          _isLoading = false;
          _calculateBalance(emitSetState: false);
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error loading expenses: $e')));
      }
    }
  }

  void _calculateBalance({bool emitSetState = true}) {
    double expenses = 0.0;
    for (final t in transactions) {
      final amount = (t["amount"] as num).toDouble();
      expenses += amount;
    }
    if (!mounted) return;
    void updateTotals() {
      _totalExpenses = expenses;
      _totalIncome = _linkedIncome;
      _totalBalance = _linkedIncome - _totalExpenses;
    }

    if (emitSetState) {
      setState(updateTotals);
    } else {
      updateTotals();
    }
  }

  Future<void> _showLinkedIncomeDialog() async {
    final TextEditingController controller = TextEditingController(
      text: _linkedIncome > 0 ? _linkedIncome.toStringAsFixed(2) : '',
    );
    final double? updatedValue = await showDialog<double>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Link Balance & Income'),
          content: TextField(
            controller: controller,
            keyboardType:
                const TextInputType.numberWithOptions(signed: false, decimal: true),
            decoration: const InputDecoration(
              labelText: 'Enter available balance',
              hintText: 'e.g. 1200.00',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final text = controller.text.trim();
                final value = double.tryParse(text);
                if (value == null) {
                  Navigator.pop(context);
                  return;
                }
                Navigator.pop(context, value);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (updatedValue == null) return;
    await FinanceService.setLinkedIncome(updatedValue);
    if (!mounted) return;
    setState(() {
      _linkedIncome = updatedValue;
      _calculateBalance(emitSetState: false);
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Linked balance updated to ${updatedValue.toStringAsFixed(2)}',
          ),
        ),
      );
    }
  }

  Future<void> _refreshData() async {
    // Pull latest from server if online
    final connectivity = Provider.of<ConnectivityProvider>(
      context,
      listen: false,
    );
    if (connectivity.isOnline) {
      setState(() => _isSyncing = true);
      try {
        final syncService = SyncService();
        await syncService.syncNow();
        await fetchExpenses();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Sync error: $e')));
        }
      } finally {
        if (mounted) {
          setState(() => _isSyncing = false);
        }
      }
    } else {
      // Just refresh local data
      await fetchExpenses();
    }
  }

  void openAddExpenseSheet() {
    final CurrencyProvider currencyProvider = context.read<CurrencyProvider>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SingleChildScrollView(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 20,
            right: 20,
            top: 25,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(50),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                "Add Expense",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 20),

              if (_linkedIncome > 0) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Linked Income: ${currencyProvider.symbol}${_linkedIncome.toStringAsFixed(2)}",
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        "Remaining Balance: ${currencyProvider.symbol}${_totalBalance.toStringAsFixed(2)}",
                        style: TextStyle(
                          fontSize: 13,
                          color: _totalBalance >= 0 ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Amount
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: "Amount (${currencyProvider.code})",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 15),

              // Category
              DropdownButtonFormField<String>(
                initialValue: selectedCategory,
                decoration: InputDecoration(
                  labelText: "Category",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: categories.map((c) {
                  return DropdownMenuItem(
                    value: c['key'] as String,
                    child: Row(
                      children: [
                        Icon(
                          c['icon'] as IconData,
                          color: c['color'] as Color,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(c['key'] as String),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (v) => setState(() => selectedCategory = v!),
              ),
              const SizedBox(height: 15),

              // Payment Method
              DropdownButtonFormField(
                initialValue: selectedPayment,
                decoration: InputDecoration(
                  labelText: "Payment Method",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                items: ["Cash", "M-Pesa", "Card"]
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) => setState(() => selectedPayment = v!),
              ),
              const SizedBox(height: 15),

              // Notes
              TextField(
                controller: noteController,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: "Notes (Optional)",
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Save button
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 55),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () {
                  addExpense();
                  Navigator.pop(context);
                },
                child: const Text(
                  "Save Expense",
                  style: TextStyle(fontSize: 17),
                ),
              ),
              const SizedBox(height: 25),
            ],
          ),
        );
      },
    );
  }

  void addExpense() async {
    if (amountController.text.isEmpty) return;

    final amount = double.parse(amountController.text);
    final DateTime createdAt = DateTime.now(); // Preserves full date and time

    // Get connectivity provider before async gap
    final connectivity = Provider.of<ConnectivityProvider>(
      context,
      listen: false,
    );

    try {
      // Generate unique ID
      final localId = _uuid.v4();

      // Save to DbService (single source of truth)
      await DbService().upsertExpense(
        ExpenseModel(
          id: localId,
          amount: amount,
          category: selectedCategory,
          date: createdAt, // Full DateTime with time preserved
          note: noteController.text.isEmpty ? null : noteController.text,
          paymentMethod: selectedPayment,
          type: TransactionType.expense,
        ),
      );

      amountController.clear();
      noteController.clear();

      // Refresh the expenses list to show the new expense (prevents duplicates)
      await fetchExpenses();

      // Trigger sync in background (non-blocking)
      if (connectivity.isOnline) {
        final syncService = SyncService();
        syncService.syncNow().catchError((e) {
          // Sync failed - will retry later when connectivity changes
          debugPrint('Background sync error: $e');
        });
      }

    } catch (e) {
      // Handle error
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error saving expense: $e')));
      }
    }
  }

  Future<void> _clearAllTransactions() async {
    if (transactions.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all transactions?'),
        content: const Text(
          'This will permanently remove every transaction currently shown in the timeline.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Delete All',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final idsToDelete = transactions
          .map((t) => t['id'])
          .whereType<String>()
          .toList();
      final dbService = DbService();
      for (final id in idsToDelete) {
        await dbService.deleteExpense(id);
      }
      if (!mounted) return;
      setState(() {
        transactions.clear();
        _calculateBalance(emitSetState: false);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All transactions deleted.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete transactions: $e')),
        );
      }
    }
  }

  Future<void> _deleteTransaction(int index) async {
    if (index < 0 || index >= transactions.length) return;
    final tx = transactions[index];
    final id = tx['id'] as String?;
    try {
      if (id != null) {
        await DbService().deleteExpense(id);
      }
      setState(() {
        transactions.removeAt(index);
        _activeTransactionIndex = null;
        _calculateBalance(emitSetState: false);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.delete_sweep, color: Colors.white),
                SizedBox(width: 8),
                Text('Transaction deleted'),
              ],
            ),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _handleLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await AuthService().signOut();
        if (mounted) {
          context.go(AppRoutes.login);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error signing out: $e')));
        }
      }
    }
  }

  void _onTabChanged(int index, {bool showMenu = false}) {
    setState(() {
      // If tapping the same tab, toggle the menu
      if (_currentIndex == index && _hoveredIndex == index) {
        _hoveredIndex = null; // Close menu if already open
        return;
      }
      // If tapping a different tab, switch to it
      _currentIndex = index;
      // Only show menu if explicitly requested (from navigation bar tap)
      _hoveredIndex = showMenu ? index : null;
    });
  }

  void _closeMenu() {
    setState(() {
      _hoveredIndex = null;
    });
  }

  List<_MenuItem> _getMenuItems(int index) {
    switch (index) {
      case 0: // Home
        return [
          _MenuItem(
            icon: Icons.dashboard,
            label: 'Overview',
            onTap: () => _onTabChanged(0),
          ),
          _MenuItem(
            icon: Icons.receipt_long,
            label: 'All Transactions',
            onTap: () {
              // Could navigate to detailed transactions view
            },
          ),
          _MenuItem(
            icon: Icons.refresh,
            label: 'Refresh',
            onTap: () => _refreshData(),
          ),
        ];
      case 1: // Add
        return [
          _MenuItem(
            icon: Icons.add,
            label: 'Add Expense',
            onTap: () {
              _onTabChanged(0);
              openAddExpenseSheet();
            },
          ),
          _MenuItem(
            icon: Icons.trending_up,
            label: 'Add Income',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AddIncomeScreen()),
              );
            },
          ),
          _MenuItem(
            icon: Icons.receipt,
            label: 'Quick Add',
            onTap: () {
              _onTabChanged(0);
              openAddExpenseSheet();
            },
          ),
        ];
      case 2: // Budgets
        return [
          _MenuItem(
            icon: Icons.account_balance_wallet,
            label: 'View Budgets',
            onTap: () => _onTabChanged(2),
          ),
          _MenuItem(
            icon: Icons.add_circle_outline,
            label: 'Create Budget',
            onTap: () {
              _onTabChanged(2);
              // Could show create budget dialog
            },
          ),
          _MenuItem(
            icon: Icons.timeline,
            label: 'Budget History',
            onTap: () {
              _onTabChanged(2);
            },
          ),
        ];
      case 3: // Planner (legacy HomePage - keep menu but show home content)
        return [
          _MenuItem(
            icon: Icons.calendar_today,
            label: 'Planner / Calendar',
            onTap: () => _onTabChanged(3),
          ),
        ];
      case 4: // Settings
        return [
          _MenuItem(
            icon: Icons.settings,
            label: 'Settings',
            onTap: () => _onTabChanged(4),
          ),
          _MenuItem(
            icon: Icons.person,
            label: 'Profile',
            onTap: () => _onTabChanged(4),
          ),
          _MenuItem(
            icon: Icons.notifications,
            label: 'Notifications',
            onTap: () => _onTabChanged(4),
          ),
          _MenuItem(
            icon: Icons.logout,
            label: 'Sign Out',
            onTap: _handleLogout,
          ),
        ];
      default:
        return [];
    }
  }

  Widget _buildCurrentScreen() {
    switch (_currentIndex) {
      case 0:
        return _buildHomeContent();
      case 2:
        return const BudgetScreen();
      case 4:
        return const SettingsScreen();
      default:
        return _buildHomeContent();
    }
  }

  Widget _buildHomeContent() {
    final connectivity = Provider.of<ConnectivityProvider>(context);

    return RefreshIndicator(
      onRefresh: _refreshData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 80),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const OfflineIndicator(),
            const SizedBox(height: 16),
            if (_isSyncing)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
                color: Colors.blue,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Syncing with server...',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            if (_isSyncing) const SizedBox(height: 16),

            // BALANCE CARD
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Total Balance",
                        style: TextStyle(color: Colors.grey[400]),
                      ),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: _showLinkedIncomeDialog,
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white,
                              backgroundColor: Colors.white.withValues(alpha: 0.08),
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                            ),
                            icon: const Icon(Icons.link),
                            label: const Text(
                              'Edit',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (connectivity.isOnline)
                            const Icon(
                              Icons.cloud_done,
                              color: Colors.greenAccent,
                              size: 20,
                            )
                          else
                            const Icon(
                              Icons.cloud_off,
                              color: Colors.orange,
                              size: 20,
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Consumer<CurrencyProvider>(
                    builder: (context, currencyProvider, child) {
                      return Text(
                        "${currencyProvider.symbol}${_totalBalance.toStringAsFixed(2)}",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 15),
                  Consumer<CurrencyProvider>(
                    builder: (context, currencyProvider, child) {
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            "Income: ${currencyProvider.symbol}${_totalIncome.toStringAsFixed(2)}",
                            style: const TextStyle(color: Colors.greenAccent),
                          ),
                          Text(
                            "Expense: ${currencyProvider.symbol}${_totalExpenses.toStringAsFixed(2)}",
                            style: const TextStyle(color: Colors.redAccent),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            if (transactions.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Highlights',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 110,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: transactions.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 12),
                        itemBuilder: (context, index) {
                          final tx = transactions[index];
                          final icon = getCategoryIcon(tx["category"] as String);
                          final Color color =
                              getCategoryColor(tx["category"] as String) ?? Colors.grey;
                          final note = tx["note"] as String?;
                          final double amount = (tx["amount"] as num).toDouble();
                          return Container(
                            width: 160,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  color.withValues(alpha: 0.15),
                                  color.withValues(alpha: 0.05),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: color.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: color.withValues(alpha: 0.2),
                                      child: Icon(icon, color: color),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        tx["category"] as String,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (note != null && note.isNotEmpty)
                                  Text(
                                    note,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                Consumer<CurrencyProvider>(
                                  builder: (_, currencyProvider, _) {
                                    return Text(
                                      "- ${currencyProvider.formatAmount(amount)}",
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  "Recent Transactions",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                if (transactions.isNotEmpty)
                  TextButton.icon(
                    onPressed: _clearAllTransactions,
                    icon: const Icon(Icons.delete_outline, size: 18),
                    label: const Text('Clear'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.redAccent,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 15),

            // TRANSACTIONS LIST
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (transactions.isEmpty)
              const Padding(
                padding: EdgeInsets.all(40.0),
                child: Center(child: Text('No transactions yet')),
              )
            else
              Column(
                children: transactions.asMap().entries.map((entry) {
                  final index = entry.key;
                  final t = entry.value;
                  final categoryIcon = getCategoryIcon(t["category"] as String);
                  final categoryColor = getCategoryColor(t["category"] as String);
                  final bool showActions = _activeTransactionIndex == index;
                  return GestureDetector(
                    onLongPress: () {
                      setState(() {
                        _activeTransactionIndex = index;
                      });
                    },
                    onTap: () {
                      if (showActions) {
                        setState(() => _activeTransactionIndex = null);
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: showActions ? Colors.red[50] : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: showActions
                            ? Border.all(
                                color: Colors.redAccent.withValues(alpha: 0.3),
                              )
                            : null,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                            Icon(
                              categoryIcon,
                              color: categoryColor ?? Colors.grey,
                              size: 24,
                            ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    t["category"] as String,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  if (t["note"] != null &&
                                      (t["note"] as String).isNotEmpty)
                                    Text(
                                      t["note"] as String,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey[600],
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ],
                          ),
                          showActions
                              ? Row(
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                                      onPressed: () => _deleteTransaction(index),
                                      tooltip: 'Delete',
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close, color: Colors.grey),
                                      onPressed: () => setState(() => _activeTransactionIndex = null),
                                      tooltip: 'Cancel',
                                    ),
                                  ],
                                )
                              : Consumer<CurrencyProvider>(
                                  builder: (_, currencyProvider, _) {
                                    final double amount = (t["amount"] as num).toDouble();
                                    final String formattedAmount =
                                        currencyProvider.formatAmount(amount.abs());
                                    return Text(
                                      "- $formattedAmount",
                                      style: const TextStyle(
                                        color: Colors.red,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                    );
                                  },
                                ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = AuthService();
    final isLoggedIn = authService.isLoggedIn;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      appBar: AppBar(
        title: const Text('Expense Tracker'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (isLoggedIn)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _handleLogout,
              tooltip: 'Sign Out',
            ),
        ],
      ),
      floatingActionButton: _currentIndex == 0
          ? FloatingActionButton(
              onPressed: openAddExpenseSheet,
              backgroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(50),
              ),
              child: const Icon(Icons.add, size: 28, color: Colors.white),
            )
          : null,
      body: SafeArea(child: _buildCurrentScreen()),
      bottomNavigationBar: isLoggedIn
          ? Stack(
              children: [
                NavigationBar(
                  selectedIndex: _currentIndex,
                  onDestinationSelected: (index) =>
                      _onTabChanged(index, showMenu: true),
                  animationDuration: const Duration(milliseconds: 300),
                  destinations: <Widget>[
                    _ExpandableNavDestination(
                      key: _menuKeys[0]!,
                      icon: Icons.dashboard_outlined,
                      selectedIcon: Icons.dashboard,
                      label: 'Home',
                      isSelected: _currentIndex == 0,
                      isHovered: _hoveredIndex == 0,
                      onHover: (bool hovering) {
                        setState(() {
                          _hoveredIndex = hovering ? 0 : null;
                        });
                      },
                      menuItems: _getMenuItems(0),
                    ),
                    _ExpandableNavDestination(
                      key: _menuKeys[1]!,
                      icon: Icons.add_circle_outlined,
                      selectedIcon: Icons.add_circle,
                      label: 'Add',
                      isSelected: _currentIndex == 1,
                      isHovered: _hoveredIndex == 1,
                      onHover: (bool hovering) {
                        setState(() {
                          _hoveredIndex = hovering ? 1 : null;
                        });
                      },
                      menuItems: _getMenuItems(1),
                    ),
                    _ExpandableNavDestination(
                      key: _menuKeys[2]!,
                      icon: Icons.account_balance_wallet_outlined,
                      selectedIcon: Icons.account_balance_wallet,
                      label: 'Budgets',
                      isSelected: _currentIndex == 2,
                      isHovered: _hoveredIndex == 2,
                      onHover: (bool hovering) {
                        setState(() {
                          _hoveredIndex = hovering ? 2 : null;
                        });
                      },
                      menuItems: _getMenuItems(2),
                    ),
                    _ExpandableNavDestination(
                      key: _menuKeys[3]!,
                      icon: Icons.calendar_today_outlined,
                      selectedIcon: Icons.calendar_today,
                      label: 'Planner',
                      isSelected: _currentIndex == 3,
                      isHovered: _hoveredIndex == 3,
                      onHover: (bool hovering) {
                        setState(() {
                          _hoveredIndex = hovering ? 3 : null;
                        });
                      },
                      menuItems: _getMenuItems(3),
                    ),
                    _ExpandableNavDestination(
                      key: _menuKeys[4]!,
                      icon: Icons.settings_outlined,
                      selectedIcon: Icons.settings,
                      label: 'Settings',
                      isSelected: _currentIndex == 4,
                      isHovered: _hoveredIndex == 4,
                      onHover: (bool hovering) {
                        setState(() {
                          _hoveredIndex = hovering ? 4 : null;
                        });
                      },
                      menuItems: _getMenuItems(4),
                    ),
                  ],
                ),
                // Render menus above navigation bar
                if (_hoveredIndex != null)
                  _ExpandingMenu(
                    key: ValueKey(_hoveredIndex),
                    menuKey: _menuKeys[_hoveredIndex!]!,
                    items: _getMenuItems(_hoveredIndex!),
                    onClose: _closeMenu,
                  ),
              ],
            )
          : null,
    );
  }
}

// Expandable Navigation Destination Widget
class _ExpandableNavDestination extends StatelessWidget {
  const _ExpandableNavDestination({
    required super.key,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.isHovered,
    required this.onHover,
    required this.menuItems,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final bool isHovered;
  final ValueChanged<bool> onHover;
  final List<_MenuItem> menuItems;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: NavigationDestination(
        icon: Icon(isSelected ? selectedIcon : icon),
        selectedIcon: Icon(selectedIcon),
        label: label,
      ),
    );
  }
}

// Menu Item Model
class _MenuItem {
  const _MenuItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
}

// Expanding Menu Widget
class _ExpandingMenu extends StatelessWidget {
  const _ExpandingMenu({
    required super.key,
    required this.menuKey,
    required this.items,
    required this.onClose,
  });

  final GlobalKey menuKey;
  final List<_MenuItem> items;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final RenderBox? renderBox =
        menuKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return const SizedBox.shrink();

    final Offset position = renderBox.localToGlobal(Offset.zero);
    final Size size = renderBox.size;
    final Size screenSize = MediaQuery.of(context).size;

    // Calculate menu width and clamp its horizontal position so it doesn't overflow the screen
    final double menuWidth = (size.width + 40).clamp(0, 200);
    double left = position.dx;
    if (left + menuWidth > screenSize.width - 8) {
      left = screenSize.width - menuWidth - 8;
    }
    if (left < 8) {
      left = 8;
    }

    return Positioned(
      left: left,
      bottom: screenSize.height - position.dy + 8,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: menuWidth,
          constraints: const BoxConstraints(maxWidth: 200),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: items.map((item) {
              return InkWell(
                onTap: () {
                  onClose(); // Close menu before executing action
                  // Use a small delay to ensure menu closes before action executes
                  Future.microtask(() => item.onTap());
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Icon(item.icon, size: 20, color: Colors.grey[700]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[800],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}
