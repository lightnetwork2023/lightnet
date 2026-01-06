# 📊 Expense Analytics Screen

## 🎯 Overview

A comprehensive expense analytics screen similar to Location Analytics, showing expenses grouped by location with filtering, summaries, and a floating action button to create new expenses.

---

## 📱 Navigation

**In Drawer Menu:**
```
EXPENSE MANAGEMENT
└─ 📝 Expense                    ← Technician & Boss
   View and manage expenses
   
└─ ✓ Approve Expenses           ← Boss only
   Review and approve
```

**Single "Expense" button instead of "Create Expense"**
- Opens ExpenseAnalyticsScreen
- Shows overview with analytics
- Floating + button to create new expense

---

## 🎨 Screen Layout

```
┌─────────────────────────────────────┐
│ ← Expense Analytics    [Filter] [⟳] │
├─────────────────────────────────────┤
│                                     │
│  ┌─────────────────────────────┐   │
│  │   This Month's Expenses     │   │
│  │   TZS 1,250,000             │   │
│  │   25 expenses               │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ 📍 MBAGALA                  ⯈│   │
│  │    15 expenses               │   │
│  │                              │   │
│  │    Total: TZS 750K           │   │
│  │                              │   │
│  │    5 Pending  8 Approved    │   │
│  │    2 Rejected                │   │
│  └─────────────────────────────┘   │
│                                     │
│  ┌─────────────────────────────┐   │
│  │ 📍 KINONDONI                ⯈│   │
│  │    10 expenses               │   │
│  │                              │   │
│  │    Total: TZS 500K           │   │
│  │                              │   │
│  │    3 Pending  7 Approved    │   │
│  └─────────────────────────────┘   │
│                                     │
│                                     │
│                      [+ New Expense]│ ← FAB
└─────────────────────────────────────┘
```

---

## 🎯 Features

### **1. Summary Header**
- Period label (This Month's Expenses, Today, etc.)
- Total amount (large, formatted with K/M)
- Expense count
- Gradient background

### **2. Location Cards**
- Location name with icon
- Expense count
- Total amount for that location
- Status badges (Pending, Approved, Rejected counts)
- Tap to see details

### **3. Floating Action Button**
- Always visible at bottom right
- "New Expense" label
- Opens ExpenseCreationScreen
- Refreshes on return

### **4. Filtering Options**
- Time period filters
- Status filters
- Custom date range
- Apply button

### **5. Location Details Modal**
- Location name header
- Summary cards (Total, Count, Status breakdown)
- List of all expenses for that location
- Scrollable list

---

## 🗓️ Time Period Filters

### **Available Periods:**
1. **Today** - Today's expenses only
2. **This Week** - Current week (Mon-Sun)
3. **This Month** - Current calendar month (default)
4. **Last Month** - Previous calendar month
5. **Last 3 Months** - Rolling 3 months
6. **This Year** - Current calendar year (Jan-now)
7. **Custom** - Pick start and end dates

### **Default:** This Month

---

## 🎨 Status Filters

### **Available Statuses:**
1. **All** - Show all expenses (default)
2. **Pending** - Only pending approval
3. **Approved** - Only approved
4. **Rejected** - Only rejected

---

## 🔄 User Flow

### **View Expenses:**
```
1. Open drawer
2. Tap "Expense"
3. See expense analytics screen
4. View this month's expenses by default
5. See locations with their totals
```

### **Filter Expenses:**
```
1. Tap filter icon (top right)
2. Select time period
3. Select status
4. Tap "Apply Filters"
5. See filtered results
```

### **View Location Details:**
```
1. Tap any location card
2. Modal opens from bottom
3. See summary for that location
4. See list of all expenses
5. Scroll through expenses
6. Close modal
```

### **Create New Expense:**
```
1. Tap + button (bottom right)
2. Opens ExpenseCreationScreen
3. Fill in details
4. Submit expense
5. Returns to analytics (refreshed)
```

---

## 💻 Code Structure

### **Main Components:**

**State Variables:**
```dart
bool _isLoading = true;
Map<String, Map<String, dynamic>> _locationExpenses = {};
double _totalExpenses = 0;
int _totalCount = 0;
String _selectedPeriod = 'thisMonth';
String _selectedStatus = 'all';
DateTime? _customStartDate;
DateTime? _customEndDate;
```

**Key Methods:**
- `_loadExpenseAnalytics()` - Fetch and aggregate expenses
- `_getDateRange()` - Calculate date range from filter
- `_showFilterOptions()` - Show filter modal
- `_showLocationExpenses()` - Show location details modal
- `_buildLocationCard()` - Build location summary card

---

## 🎯 Data Structure

### **Location Expense Data:**
```dart
{
  'location': 'MBAGALA',
  'total': 750000.0,
  'count': 15,
  'pending': 5,
  'approved': 8,
  'rejected': 2,
  'expenses': [
    {
      'id': 'EXP-123...',
      'title': 'Network Equipment',
      'total_amount': 50000,
      'status': 'approved',
      'submitted_at': Timestamp(...),
      ...
    },
    ...
  ]
}
```

---

## 🎨 UI Components

### **Summary Header (Gradient Card):**
- Primary gradient background
- White text
- Large amount (32px)
- Shadow effect

### **Location Cards:**
- White background
- Location icon (blue circle)
- Chevron right (clickable)
- Total amount (highlighted box)
- Status badges (colored)

### **Status Badges:**
- Orange background/border - Pending
- Green background/border - Approved
- Red background/border - Rejected
- Small, rounded, with count

### **Floating Action Button:**
- Extended FAB with icon + label
- Primary color background
- Bottom right position
- "New Expense" text

---

## 📊 Aggregation Logic

### **Firestore Query:**
```dart
collection('expenses')
  .where('submitted_at', isGreaterThanOrEqualTo: startDate)
  .where('submitted_at', isLessThanOrEqualTo: endDate)
```

### **Client-Side Aggregation:**
```dart
// Group by location
for (expense in expenses) {
  location = expense['location_id'];
  
  locationData[location]['total'] += amount;
  locationData[location]['count']++;
  locationData[location][status]++;  // pending/approved/rejected
  locationData[location]['expenses'].add(expense);
}
```

---

## 🔍 Empty States

### **No Expenses:**
```
┌─────────────────────────────────────┐
│                                     │
│           📝 (gray icon)            │
│                                     │
│       No expenses found             │
│                                     │
│  Tap + to create your first expense │
│                                     │
└─────────────────────────────────────┘
```

### **No Expenses for Filter:**
Shows same empty state with appropriate message based on filter.

---

## 🧪 Testing Scenarios

### **Test 1: Default View (This Month)**
```
✅ Open Expense screen
✅ Shows "This Month's Expenses"
✅ Shows current month's data
✅ Locations sorted by total
✅ Totals are accurate
```

### **Test 2: Filter by Period**
```
✅ Tap filter icon
✅ Select "Last Month"
✅ Apply filter
✅ Shows last month's data
✅ Header updates
```

### **Test 3: Filter by Status**
```
✅ Tap filter icon
✅ Select "Pending"
✅ Apply filter
✅ Only pending expenses shown
✅ Counts are correct
```

### **Test 4: Custom Date Range**
```
✅ Tap filter icon
✅ Select "Custom"
✅ Pick start date
✅ Pick end date
✅ Apply filter
✅ Shows expenses in range
```

### **Test 5: Location Details**
```
✅ Tap location card
✅ Modal opens
✅ Shows summary cards
✅ Shows expense list
✅ List is scrollable
✅ Close button works
```

### **Test 6: Create New Expense**
```
✅ Tap + button
✅ Opens creation screen
✅ Create expense
✅ Returns to analytics
✅ New expense visible
✅ Totals updated
```

### **Test 7: Refresh**
```
✅ Tap refresh icon
✅ Shows loading
✅ Data reloads
✅ Totals recalculated
```

### **Test 8: Pull to Refresh**
```
✅ Pull down on list
✅ Refresh indicator shows
✅ Data reloads
✅ List updates
```

---

## 🎨 Visual Design

### **Colors:**
- Primary: Blue (#2196F3)
- Pending: Orange
- Approved: Green
- Rejected: Red
- Background: Light gray

### **Typography:**
- Header amount: 32px, bold
- Location name: 16px, bold
- Subtitles: 12px, gray
- Amount: 18px, bold, primary color

### **Spacing:**
- Card margin: 16px bottom
- Internal padding: 16px all sides
- Section spacing: 24px

---

## 📁 Files

### **New Files:**
1. ✅ `lib/screens/ExpenseAnalyticsScreen.dart` - Main screen

### **Modified Files:**
1. ✅ `lib/widgets/modern_drawer.dart` - Updated navigation
   - Changed "Create Expense" to "Expense"
   - Links to ExpenseAnalyticsScreen
   - Kept "Approve Expenses" for boss

---

## 🔄 Navigation Updates

### **Before:**
```
EXPENSE MANAGEMENT
├─ Create Expense      (Technician/Boss)
└─ Approve Expenses    (Boss)
```

### **After:**
```
EXPENSE MANAGEMENT
├─ Expense             (Technician/Boss) ← NEW!
│  → ExpenseAnalyticsScreen
│  → FAB to create expense
└─ Approve Expenses    (Boss)
   → ExpenseApprovalScreen
```

---

## 💡 Benefits

### **User Experience:**
- ✅ See expense overview at a glance
- ✅ Filter by time and status
- ✅ Group expenses by location
- ✅ Quick access to create new expense
- ✅ Drill down into location details
- ✅ Consistent with Location Analytics

### **Business Value:**
- 📊 Track expenses by location
- 💰 Monitor spending patterns
- 📈 Compare periods
- 🎯 Identify high-cost locations
- ✅ Better financial visibility

---

## 🚀 Future Enhancements

### **Potential Additions:**
- [ ] Charts/graphs for visual trends
- [ ] Export to CSV/PDF
- [ ] Budget comparisons
- [ ] Category breakdown
- [ ] Approval rate metrics
- [ ] Search expenses
- [ ] Sort options (amount, date, status)
- [ ] Quick stats (avg per location, etc.)

---

## ✅ Summary

**What's New:**
- ✅ ExpenseAnalyticsScreen created
- ✅ Summary header with total
- ✅ Location-based cards
- ✅ Time period filtering
- ✅ Status filtering
- ✅ Custom date range
- ✅ Location details modal
- ✅ Floating action button for new expense
- ✅ Single "Expense" button in drawer

**User Flow:**
```
Drawer → Expense → Analytics Screen → + Button → Create Expense
                 ↓
          Location Card → Details Modal → Expense List
```

**Expense analytics screen is ready with full filtering and location grouping!** 📊✅
