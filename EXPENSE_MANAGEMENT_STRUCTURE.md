# 💰 Expense Management System - Structure

## 🎯 Overview
Complete expense tracking system with cart-based creation, approval workflow, and location analytics integration.

---

## 📊 Firestore Collections

### **1. expenses (Main Collection)**

```javascript
expenses/{expenseId} {
  // Basic Info
  expense_id: "EXP-2024-001",
  title: "Network Equipment Purchase",
  description: "Routers and cables for MBAGALA expansion",
  
  // Items (Cart)
  items: [
    {
      name: "Router TP-Link",
      quantity: 5,
      unit_price: 150000,
      total_price: 750000
    },
    {
      name: "Ethernet Cable (100m)",
      quantity: 10,
      unit_price: 50000,
      total_price: 500000
    },
    {
      name: "Power Socket",
      quantity: 15,
      unit_price: 5000,
      total_price: 75000
    }
  ],
  
  // Financial
  total_amount: 1325000,
  currency: "TZS",
  
  // Location
  location_id: "MBAGALA",
  location_name: "MBAGALA",
  
  // Submission
  submitted_by: "agent@email.com",
  submitted_by_name: "John Doe",
  submitted_at: Timestamp,
  
  // Approval
  status: "pending",  // pending, approved, rejected
  approved_by: null,
  approved_by_name: null,
  approved_at: null,
  rejection_reason: null,
  
  // Metadata
  created_at: Timestamp,
  updated_at: Timestamp,
  
  // Attachments (optional)
  receipt_url: "https://...",
  notes: "Urgent - needed for expansion"
}
```

---

## 🔐 Status Flow

```
1. PENDING
   ↓
   Boss reviews
   ↓
2. APPROVED or REJECTED
   ↓
   (Final state)
```

### **Status Details:**

**PENDING:**
- Just submitted
- Waiting for approval
- Boss can approve/reject
- Submitter cannot modify

**APPROVED:**
- Boss approved
- Counted in expenses
- Shown in location analytics
- Immutable

**REJECTED:**
- Boss rejected
- Not counted in expenses
- Shows rejection reason
- Can create new expense

---

## 👥 Roles & Permissions

### **Agent/Superagent:**
- ✅ Create expenses
- ✅ Add items to cart
- ✅ Select location
- ✅ Submit for approval
- ✅ View own expenses
- ❌ Cannot approve own expenses
- ❌ Cannot approve any expenses

### **Boss:**
- ✅ View all expenses
- ✅ Approve expenses (not own)
- ✅ Reject expenses (not own)
- ✅ Add rejection reason
- ✅ View expense analytics
- ❌ Cannot approve own submissions

---

## 🛒 Cart Structure

### **Expense Item:**
```dart
class ExpenseItem {
  String name;         // Item name
  int quantity;        // Quantity
  double unitPrice;    // Price per unit
  double totalPrice;   // quantity * unitPrice
}
```

### **Example Cart:**
```
┌─────────────────────────────────────┐
│ Cart Items (3)                      │
├─────────────────────────────────────┤
│ Router TP-Link                      │
│ Qty: 5  × 150,000 = 750,000        │
│                              [×]    │
├─────────────────────────────────────┤
│ Ethernet Cable                      │
│ Qty: 10 × 50,000 = 500,000         │
│                              [×]    │
├─────────────────────────────────────┤
│ Power Socket                        │
│ Qty: 15 × 5,000 = 75,000           │
│                              [×]    │
├─────────────────────────────────────┤
│ Total: TZS 1,325,000               │
└─────────────────────────────────────┘
```

---

## 📱 Screens

### **1. ExpenseCreationScreen**
- Add items to cart
- Edit quantities and prices
- Select location
- Submit for approval

### **2. ExpenseApprovalScreen** (Boss only)
- View pending expenses
- See expense details
- Approve or reject
- Add rejection reason

### **3. ExpenseListScreen**
- View own expenses (filtered by user)
- See status (pending/approved/rejected)
- Filter by location
- Filter by status

### **4. LocationAnalyticsScreen** (Enhanced)
- Show total expenses per location
- Compare revenue vs expenses
- Profit/loss calculation
- Expense breakdown

---

## 🔄 Workflows

### **Workflow 1: Create & Submit Expense**

```
Agent Opens ExpenseCreationScreen
    ↓
1. Enter title & description
    ↓
2. Add items to cart:
   - Item name
   - Quantity
   - Unit price
   - Auto-calculate total
    ↓
3. Select location
    ↓
4. Review cart (total)
    ↓
5. Submit
    ↓
Expense created (status: pending)
    ↓
Notification to boss
```

### **Workflow 2: Boss Approval**

```
Boss Opens ExpenseApprovalScreen
    ↓
See pending expenses
    ↓
Tap expense to view details:
- Title & description
- Location
- Items list
- Total amount
- Submitted by
    ↓
Decision:
- Approve → Status: approved
- Reject → Enter reason → Status: rejected
    ↓
Notification to submitter
```

### **Workflow 3: View in Analytics**

```
Open LocationAnalyticsScreen
    ↓
Select location (e.g., MBAGALA)
    ↓
See stats:
- Revenue: TZS 5,000,000
- Expenses: TZS 1,325,000
- Profit: TZS 3,675,000
- Profit Margin: 73.5%
    ↓
Tap for expense breakdown
```

---

## 📊 Analytics Integration

### **Location Stats Enhanced:**

```dart
class LocationStats {
  // Existing
  String locationId;
  double totalRevenue;
  int paymentCount;
  
  // NEW - Expenses
  double totalExpenses;
  int expenseCount;
  
  // Calculated
  double profit;           // revenue - expenses
  double profitMargin;     // (profit / revenue) * 100
  bool isProfitable;       // profit > 0
}
```

### **Location Card with Expenses:**

```
┌─────────────────────────────────────┐
│ 🏆 #1 MBAGALA                      │
│ 🌳 5 sublocations                   │
├─────────────────────────────────────┤
│ Revenue     | Expenses  | Profit    │
│ 5.0M        | 1.3M      | 3.7M      │
│                                     │
│ Payments    | Margin    | Last      │
│ 350         | 73.5%     | 1h ago    │
└─────────────────────────────────────┘
```

---

## 🔍 Queries

### **Get Pending Expenses:**
```dart
FirebaseFirestore.instance
  .collection('expenses')
  .where('status', isEqualTo: 'pending')
  .orderBy('submitted_at', descending: true)
  .snapshots();
```

### **Get Expenses by Location:**
```dart
FirebaseFirestore.instance
  .collection('expenses')
  .where('location_id', isEqualTo: locationId)
  .where('status', isEqualTo: 'approved')
  .snapshots();
```

### **Get User's Expenses:**
```dart
FirebaseFirestore.instance
  .collection('expenses')
  .where('submitted_by', isEqualTo: userEmail)
  .orderBy('submitted_at', descending: true)
  .snapshots();
```

### **Get Location Total Expenses:**
```dart
// Aggregate approved expenses only
final expenses = await FirebaseFirestore.instance
  .collection('expenses')
  .where('location_id', isEqualTo: locationId)
  .where('status', isEqualTo: 'approved')
  .get();

double total = expenses.docs.fold(0.0, (sum, doc) => 
  sum + (doc.data()['total_amount'] as num).toDouble()
);
```

---

## 🎯 Validation Rules

### **Create Expense:**
- ✅ Title required (min 3 chars)
- ✅ At least 1 item in cart
- ✅ All items must have:
  - Name (not empty)
  - Quantity > 0
  - Unit price > 0
- ✅ Location must be selected
- ✅ Total amount must be > 0

### **Approve/Reject:**
- ✅ Must be boss role
- ✅ Cannot approve own expense
- ✅ Expense must be pending
- ✅ Rejection requires reason

---

## 🔔 Notifications (Optional - Future Enhancement)

### **To Boss:**
- New expense submitted
- Action required

### **To Submitter:**
- Expense approved
- Expense rejected (with reason)

---

## 💡 Features Summary

### **Core Features:**
1. ✅ Cart-based expense creation
2. ✅ Multi-item support
3. ✅ Location assignment
4. ✅ Approval workflow
5. ✅ Cannot approve own expenses
6. ✅ Rejection with reason
7. ✅ Status tracking
8. ✅ Analytics integration

### **Analytics Features:**
1. ✅ Revenue vs Expenses
2. ✅ Profit calculation
3. ✅ Profit margin %
4. ✅ Expense breakdown
5. ✅ Per-location analysis
6. ✅ Time period filtering

### **Business Intelligence:**
1. ✅ Identify high-cost locations
2. ✅ Track profitability
3. ✅ Expense trends
4. ✅ Budget monitoring
5. ✅ ROI analysis

---

## 📈 Example Scenarios

### **Scenario 1: Equipment Purchase**
```
MBAGALA needs network equipment
    ↓
Agent creates expense:
- Title: "Network Equipment"
- Items:
  * 5 Routers @ 150,000 = 750,000
  * 10 Cables @ 50,000 = 500,000
- Location: MBAGALA
- Total: 1,250,000
    ↓
Submit → Status: Pending
    ↓
Boss reviews → Approves
    ↓
Status: Approved
    ↓
Shows in MBAGALA analytics:
- Revenue: 5,000,000
- Expenses: 1,250,000
- Profit: 3,750,000 (75% margin)
```

### **Scenario 2: Rejected Expense**
```
Agent submits expense:
- Title: "Personal Items"
- Total: 500,000
    ↓
Boss reviews → Rejects
Reason: "Not business related"
    ↓
Status: Rejected
    ↓
NOT counted in analytics
Agent notified with reason
```

### **Scenario 3: Cannot Approve Own**
```
Boss creates expense:
- Title: "Office Supplies"
- Total: 200,000
    ↓
Submit → Status: Pending
    ↓
Boss tries to approve own expense
    ↓
❌ Blocked: "Cannot approve your own expense"
    ↓
Needs another boss to approve
```

---

## ✅ Implementation Checklist

### **Phase 1: Core Screens**
- [ ] ExpenseCreationScreen (cart UI)
- [ ] ExpenseApprovalScreen (boss)
- [ ] ExpenseListScreen (view own)

### **Phase 2: Integration**
- [ ] Add expenses to LocationAnalyticsScreen
- [ ] Revenue vs Expenses display
- [ ] Profit calculation

### **Phase 3: Features**
- [ ] Approval workflow
- [ ] Self-approval prevention
- [ ] Rejection reasons
- [ ] Status filtering

### **Phase 4: Polish**
- [ ] Loading states
- [ ] Error handling
- [ ] Validation
- [ ] Success messages

---

**Ready to implement comprehensive expense management!** 💰
