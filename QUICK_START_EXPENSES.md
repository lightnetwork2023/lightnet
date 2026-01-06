# 🚀 Quick Start - Expense Management

## ✅ What's Been Created

### **1. Core Screens:**
- ✅ `ExpenseCreationScreen.dart` - Create expenses with shopping cart
- ✅ `ExpenseApprovalScreen.dart` - Approve/reject expenses (Boss)

### **2. Key Features:**
- ✅ Cart-based item addition
- ✅ Location selection
- ✅ Approval workflow
- ✅ **Cannot approve own expenses** 🔒
- ✅ Rejection with reason

---

## 🔧 How to Use

### **1. Add to Navigation (Drawer/Menu):**

```dart
// For all users (create expense)
ListTile(
  leading: Icon(Icons.receipt_long),
  title: Text('Create Expense'),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ExpenseCreationScreen(),
      ),
    );
  },
),

// For boss only (approve expenses)
if (userRole == 'boss')
  ListTile(
    leading: Icon(Icons.approval),
    title: Text('Approve Expenses'),
    badge: StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('expenses')
          .where('status', isEqualTo: 'pending')
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        return count > 0 ? Badge(label: Text('$count')) : SizedBox.shrink();
      },
    ),
    onTap: () {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ExpenseApprovalScreen(),
        ),
      );
    },
  ),
```

---

## 📊 Firestore Collection Created

**Collection:** `expenses`

**Document Structure:**
```javascript
{
  expense_id: "EXP-timestamp",
  title: "Network Equipment",
  items: [
    {name: "Router", quantity: 5, unit_price: 150000, total_price: 750000}
  ],
  total_amount: 1325000,
  location_id: "MBAGALA",
  submitted_by: "user@email.com",
  status: "pending", // pending | approved | rejected
  ...
}
```

---

## 🎯 Next Step: Analytics Integration

**Add expenses to Location Analytics:**

```dart
// In LocationAnalyticsScreen, query expenses:
final expenses = await _firestore
  .collection('expenses')
  .where('location_id', isEqualTo: locationId)
  .where('status', isEqualTo: 'approved')
  .where('submitted_at', isGreaterThan: periodStart)
  .where('submitted_at', isLessThan: periodEnd)
  .get();

double totalExpenses = expenses.docs.fold(0.0, 
  (sum, doc) => sum + doc.data()['total_amount']
);

// Calculate profit
double profit = totalRevenue - totalExpenses;
double profitMargin = (profit / totalRevenue) * 100;

// Display
Revenue:  5,000,000
Expenses: 1,325,000
────────────────
Profit:   3,675,000 (73.5%)
```

---

## ✅ Testing

**1. Create Expense:**
```
1. Open ExpenseCreationScreen
2. Fill title & description
3. Select location
4. Add items to cart
5. Submit
✅ Status: pending
```

**2. Approve (Boss):**
```
1. Open ExpenseApprovalScreen
2. Tap expense
3. Review details
4. Click "Approve"
✅ Status: approved
```

**3. Self-Approval Prevention:**
```
1. Boss creates expense
2. Boss tries to approve
❌ Error: "Cannot approve your own expense"
```

---

## 📁 Files Created

1. `lib/screens/ExpenseCreationScreen.dart`
2. `lib/screens/ExpenseApprovalScreen.dart`
3. `EXPENSE_MANAGEMENT_STRUCTURE.md`
4. `EXPENSE_MANAGEMENT_COMPLETE.md`
5. `QUICK_START_EXPENSES.md` (this file)

---

**Ready to track expenses by location!** 💰
