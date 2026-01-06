# ✅ Edit Expense Before Approval Feature

## 🎯 New Feature Added

Bosses can now **edit expenses before approving** them! An "EDIT" button has been added to the approval dialog, allowing modifications to pending expenses before making a decision.

---

## 🎨 Updated Approval Dialog

### **New Button Layout:**
```
┌─────────────────────────────────┐
│ 🔔 Office Supplies              │
│    PENDING APPROVAL             │
│    🛒 3 items                   │
├─────────────────────────────────┤
│ [Content with items...]         │
├─────────────────────────────────┤
│ TOTAL            TZS 50,000     │
├─────────────────────────────────┤
│ [📝 EDIT EXPENSE]  ← NEW!       │
│                                 │
│ [🚫 REJECT]  [✅ APPROVE]       │
└─────────────────────────────────┘
```

**Three Actions:**
1. **📝 EDIT EXPENSE** (Blue, full width, outlined)
2. **🚫 REJECT** (Red, left)
3. **✅ APPROVE** (Green, right)

---

## 🔧 How It Works

### **User Flow:**

**1. View Pending Expense:**
```
Approvals Tab
  → Click pending expense card
    → Dialog opens with details
```

**2. Click EDIT:**
```
Click "EDIT EXPENSE" button
  → Dialog closes
  → Opens ExpenseCreationScreen
  → Form pre-filled with existing data
```

**3. Make Changes:**
```
Edit any field:
  ✏️ Title
  ✏️ Description
  ✏️ Location
  ✏️ Items (add, remove, modify)
  ✏️ Quantities
  ✏️ Prices
  ✏️ Notes
```

**4. Save Changes:**
```
Click "UPDATE EXPENSE"
  → Expense updated in Firestore
  → Returns to Approvals tab
  → Updated expense still pending
```

**5. Approve Updated Expense:**
```
Click expense again
  → See updated details
  → Click "APPROVE"
  → Done! ✅
```

---

## 📝 Technical Implementation

### **1. ExpenseAnalyticsScreen.dart**

**Added Edit Button to Approval Dialog:**
```dart
// Action Buttons
Container(
  child: Column(
    children: [
      // NEW: Edit Button (Full Width)
      SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => _editExpense(expense, expenseId),
          icon: const Icon(Icons.edit),
          label: const Text('EDIT EXPENSE'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.blue,
            side: const BorderSide(color: Colors.blue, width: 2),
          ),
        ),
      ),
      const SizedBox(height: 12),
      // Reject and Approve Buttons
      Row(
        children: [
          Expanded(child: RejectButton()),
          Expanded(child: ApproveButton()),
        ],
      ),
    ],
  ),
)
```

**Added `_editExpense` Method:**
```dart
void _editExpense(Map<String, dynamic> expense, String expenseId) {
  Navigator.pop(context); // Close approval dialog
  
  // Navigate to ExpenseCreationScreen with existing data
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => ExpenseCreationScreen(
        expenseId: expenseId,
        existingExpense: expense,
      ),
    ),
  ).then((_) {
    // Refresh approvals list after editing
    setState(() {});
  });
}
```

---

### **2. ExpenseCreationScreen.dart**

**Added Constructor Parameters:**
```dart
class ExpenseCreationScreen extends StatefulWidget {
  final String? expenseId;              // ← NEW: For editing
  final Map<String, dynamic>? existingExpense;  // ← NEW: For editing

  const ExpenseCreationScreen({
    Key? key,
    this.expenseId,
    this.existingExpense,
  }) : super(key: key);
}
```

**Added `_populateExistingData` Method:**
```dart
void _populateExistingData() {
  if (widget.existingExpense != null) {
    final expense = widget.existingExpense!;
    
    // Populate basic fields
    _titleController.text = expense['title'] ?? '';
    _descriptionController.text = expense['description'] ?? '';
    _notesController.text = expense['notes'] ?? '';
    _selectedLocation = expense['location_id'] ?? expense['location_name'];
    
    // Populate cart items
    final items = expense['items'] as List<dynamic>? ?? [];
    _cartItems = items.map((item) {
      final itemData = item as Map<String, dynamic>;
      return ExpenseItem(
        name: itemData['name'] ?? '',
        quantity: (itemData['quantity'] as num?)?.toInt() ?? 1,
        unitPrice: (itemData['unit_price'] as num?)?.toDouble() ?? 0,
        totalPrice: (itemData['total_price'] as num?)?.toDouble() ?? 0,
      );
    }).toList();
    
    setState(() {});
  }
}
```

**Modified `_submitExpense` to Handle Updates:**
```dart
Future<void> _submitExpense() async {
  // Validation...
  
  final expenseData = {
    'title': _titleController.text.trim(),
    'description': _descriptionController.text.trim(),
    'items': itemsData,
    'total_amount': _totalAmount,
    'currency': 'TZS',
    'location_id': _selectedLocation,
    'location_name': _selectedLocation,
    'notes': _notesController.text.trim(),
    'updated_at': FieldValue.serverTimestamp(),
  };
  
  if (widget.expenseId != null) {
    // UPDATE existing expense
    await _firestore.collection('expenses').doc(widget.expenseId).update(expenseData);
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ Expense updated successfully')),
    );
  } else {
    // CREATE new expense
    expenseData.addAll({
      'expense_id': expenseId,
      'submitted_by': user.email,
      'submitted_at': FieldValue.serverTimestamp(),
      'status': 'pending',
      // ... other fields
    });
    
    await _firestore.collection('expenses').doc(expenseId).set(expenseData);
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('✅ Expense submitted for approval')),
    );
  }
}
```

**Updated UI Text:**
```dart
// AppBar Title
AppBar(
  title: Text(
    widget.expenseId != null ? 'Edit Expense' : 'Create Expense',
  ),
)

// Submit Button Text
ElevatedButton(
  child: Text(
    widget.expenseId != null ? 'Update Expense' : 'Submit for Approval',
  ),
)
```

---

## 📊 Firestore Updates

### **When Editing:**
```javascript
// Only updates specified fields
{
  "title": "Updated Title",
  "description": "Updated Description",
  "items": [...updated items...],
  "total_amount": 60000,  // Recalculated
  "location_id": "Main Office",
  "notes": "Updated notes",
  "updated_at": Timestamp  // Updated timestamp
  
  // Preserved fields (not changed):
  "expense_id": "EXP-123",
  "submitted_by": "tech@example.com",
  "submitted_at": Timestamp,  // Original
  "status": "pending",  // Still pending
  "created_at": Timestamp  // Original
}
```

**Key Points:**
- ✅ Updates only modified fields
- ✅ Preserves original submission data
- ✅ Status remains "pending"
- ✅ Updated timestamp added
- ✅ Submitter info unchanged

---

## 🎯 Use Cases

### **Case 1: Correct Wrong Amount**
```
Technician submitted:
  - Office Supplies: TZS 50,000
  
Boss notices error:
  - Should be TZS 55,000
  
Boss clicks EDIT:
  - Updates item price
  - Saves changes
  - Reviews updated expense
  - Approves ✅
```

### **Case 2: Add Missing Item**
```
Technician submitted:
  - Pens: TZS 10,000
  
Boss realizes missing:
  - Paper was also purchased
  
Boss clicks EDIT:
  - Adds new item: Paper - TZS 20,000
  - Total updates to TZS 30,000
  - Saves changes
  - Approves ✅
```

### **Case 3: Change Location**
```
Technician selected:
  - Location: Main Office
  
Boss knows correct location:
  - Should be: Branch A
  
Boss clicks EDIT:
  - Changes location dropdown
  - Saves changes
  - Approves ✅
```

### **Case 4: Fix Description**
```
Technician wrote:
  - Description: "stuff"
  
Boss wants clarity:
  - Needs proper description
  
Boss clicks EDIT:
  - Updates description: "Network cables and connectors"
  - Saves changes
  - Approves ✅
```

---

## ✅ Benefits

### **For Bosses:**
- 🔧 **Fix errors** without rejecting
- ⚡ **Faster approval** - no back-and-forth
- ✏️ **Add clarity** to descriptions
- 📝 **Complete incomplete** submissions
- 🎯 **Accurate records** before approval

### **For Technicians:**
- 😊 **Less rejection** - boss can fix minor issues
- ⏱️ **Faster processing** - no resubmission needed
- 📚 **Learn from edits** - see what was changed
- ✅ **More approvals** - corrections don't mean rejection

### **For Organization:**
- 📊 **Accurate data** - corrected before approval
- 🔄 **Efficient workflow** - less back-and-forth
- 💾 **Complete records** - all info captured
- ⚡ **Faster processing** - approve on first review

---

## 🧪 Testing

### **Test Edit Flow:**

1. **Create pending expense** as technician
2. Switch to **boss account**
3. Go to **Approvals tab**
4. **Click** pending expense
5. **Verify:**
   - ✅ EDIT EXPENSE button visible (blue, full width)
   - ✅ Above REJECT and APPROVE buttons

6. **Click EDIT EXPENSE**
7. **Verify:**
   - ✅ Dialog closes
   - ✅ Edit screen opens
   - ✅ Title: "Edit Expense"
   - ✅ All fields pre-filled with existing data
   - ✅ Cart items loaded correctly
   - ✅ Location selected
   - ✅ Button text: "Update Expense"

8. **Make changes:**
   - Edit title
   - Change an item quantity
   - Add new item
   - Update description

9. **Click UPDATE EXPENSE**
10. **Verify:**
    - ✅ Success message: "Expense updated successfully"
    - ✅ Returns to Approvals tab
    - ✅ Expense still in pending list

11. **Click expense again**
12. **Verify:**
    - ✅ Shows updated details
    - ✅ All changes reflected
    - ✅ Can still approve or reject

13. **Click APPROVE**
14. **Verify:**
    - ✅ Expense approved
    - ✅ Removed from pending
    - ✅ Appears in Analytics

---

## 🎨 UI Design

### **Edit Button Styling:**
```dart
OutlinedButton.icon(
  foregroundColor: Colors.blue,  // Blue text and icon
  side: BorderSide(color: Colors.blue, width: 2),  // Blue border
  icon: Icon(Icons.edit),  // Edit icon
  label: Text('EDIT EXPENSE'),  // Clear label
)
```

**Design Choices:**
- 🔵 **Blue** - Neutral action (not destructive, not approval)
- 📝 **Edit icon** - Clear intent
- 📏 **Full width** - Primary action visibility
- 🔲 **Outlined** - Distinguishes from solid action buttons
- ⬆️ **Above actions** - Logical flow (edit before deciding)

---

## 🔄 Workflow Comparison

### **Before (Without Edit):**
```
Pending Expense → Boss reviews
  ↓
  Error found ❌
  ↓
  Boss REJECTS
  ↓
  Technician resubmits
  ↓
  Boss reviews again
  ↓
  Boss APPROVES
  
Total: 4 steps, 2 reviews
```

### **After (With Edit):**
```
Pending Expense → Boss reviews
  ↓
  Error found
  ↓
  Boss EDITS
  ↓
  Boss APPROVES
  
Total: 2 steps, 1 review ✅
```

**Saved:** 2 steps, 1 review cycle!

---

## ⚠️ Important Notes

### **Editing Behavior:**
- ✅ Expense remains **pending** after editing
- ✅ Status doesn't change to "approved" automatically
- ✅ Boss must still **approve** after editing
- ✅ Edit is optional - can approve directly without editing

### **Data Preservation:**
- ✅ Original submission info preserved
- ✅ Submitter info unchanged
- ✅ Original timestamp kept
- ✅ Only updated fields change
- ✅ `updated_at` timestamp added

### **Permissions:**
- ✅ Only accessible from Approvals tab
- ✅ Only bosses see Approvals tab
- ✅ Technicians can't edit after submission
- ✅ Edit button only on pending expenses

---

## 📋 Summary

### **What Was Added:**
- 📝 **EDIT button** in approval dialog
- 🔄 **Edit mode** in ExpenseCreationScreen
- ✏️ **Pre-fill form** with existing data
- 💾 **Update operation** instead of create
- 🎨 **Dynamic UI text** (Edit vs Create)

### **Key Features:**
- ✅ Edit title, description, items, prices, location
- ✅ Add/remove/modify cart items
- ✅ Changes saved to Firestore
- ✅ Expense remains pending
- ✅ Can approve after editing

### **Benefits:**
- ⚡ Faster approval workflow
- 🔧 Fix errors without rejection
- 📊 More accurate data
- 😊 Better user experience
- 💾 Complete expense records

---

## 🎉 Result

**Bosses can now edit expenses before approving them!**

- 📝 Fix errors on the spot
- ⚡ Approve faster
- 📊 Ensure accuracy
- 🔄 Streamlined workflow
- ✅ Better expense management

**Your expense approval process is now more flexible and efficient!** 🎉✨
