# 🔒 Expense Creation - Role Restriction

## 🎯 Access Control

**Only these roles can create expenses:**
- ✅ **Technician** - Can create expenses
- ✅ **Boss** - Can create expenses
- ❌ **Agent** - Cannot create expenses
- ❌ **Superagent** - Cannot create expenses
- ❌ **Other roles** - Cannot create expenses

---

## 🔐 How It Works

### **Role Check on Screen Load:**

```dart
@override
void initState() {
  super.initState();
  _checkUserRole();  // Check role first
  _loadLocations();
}

Future<void> _checkUserRole() async {
  // Get user from Firebase Auth
  final user = FirebaseAuth.instance.currentUser;
  
  // Get role from Firestore users collection
  final userDoc = await FirebaseFirestore.instance
      .collection('users')
      .doc(user.email)
      .get();
  
  final role = userDoc.data()?['role'];
  
  // Only technician and boss can access
  _hasAccess = role == 'technician' || role == 'boss';
}
```

---

## 📱 User Experience

### **For Technician/Boss (Allowed):**

```
Open ExpenseCreationScreen
    ↓
Check role → ✅ technician/boss
    ↓
Show expense creation form
    ↓
Create expense normally
```

### **For Agent/Superagent (Blocked):**

```
Open ExpenseCreationScreen
    ↓
Check role → ❌ agent/superagent
    ↓
Show "Access Denied" screen
    ↓
┌─────────────────────────────────────┐
│           🚫                        │
│                                     │
│      Access Denied                  │
│                                     │
│  Only Technicians and Boss can      │
│  create expenses.                   │
│                                     │
│  Your role: agent                   │
│                                     │
│        [← Go Back]                  │
└─────────────────────────────────────┘
```

---

## 🎨 Access Denied Screen

```
┌─────────────────────────────────────┐
│   Create Expense                    │
├─────────────────────────────────────┤
│                                     │
│           🚫 (large)                │
│                                     │
│      Access Denied                  │
│      (red, bold)                    │
│                                     │
│  Only Technicians and Boss          │
│  can create expenses.               │
│                                     │
│  ┌─────────────────┐               │
│  │ Your role: agent │               │
│  └─────────────────┘               │
│                                     │
│  ┌───────────────────┐             │
│  │ ← Go Back         │             │
│  └───────────────────┘             │
│                                     │
└─────────────────────────────────────┘
```

---

## 🔄 States

### **State 1: Checking Role (Loading)**
```
┌─────────────────────────────────────┐
│   Create Expense                    │
├─────────────────────────────────────┤
│                                     │
│           ⟳                         │
│        Loading...                   │
│                                     │
└─────────────────────────────────────┘
```

### **State 2: Access Granted (Technician/Boss)**
```
┌─────────────────────────────────────┐
│   Create Expense                    │
├─────────────────────────────────────┤
│ ℹ️ Basic Information                │
│ Title: [________________]           │
│ Description: [__________]           │
│ Location: [MBAGALA ▼]              │
│                                     │
│ 🛒 Add Items to Cart               │
│ ...                                 │
└─────────────────────────────────────┘
```

### **State 3: Access Denied (Other Roles)**
```
┌─────────────────────────────────────┐
│   Create Expense                    │
├─────────────────────────────────────┤
│           🚫                        │
│      Access Denied                  │
│  Only Technicians and Boss          │
│  can create expenses.               │
│  Your role: agent                   │
│        [← Go Back]                  │
└─────────────────────────────────────┘
```

---

## 💾 Firestore User Structure

```javascript
users/{userEmail} {
  email: "user@email.com",
  name: "John Doe",
  role: "technician",  // or "boss", "agent", "superagent"
  location: "MBAGALA",
  locations: ["MBAGALA", "KINONDONI"],  // for superagent
  created_at: Timestamp
}
```

**Role values:**
- `"boss"` → ✅ Can create expenses
- `"technician"` → ✅ Can create expenses
- `"agent"` → ❌ Cannot create expenses
- `"superagent"` → ❌ Cannot create expenses

---

## 🧪 Testing Scenarios

### **Test 1: Technician Access**
```
1. Login as technician
2. Open ExpenseCreationScreen
✅ Shows expense creation form
✅ Can create expenses
```

### **Test 2: Boss Access**
```
1. Login as boss
2. Open ExpenseCreationScreen
✅ Shows expense creation form
✅ Can create expenses
```

### **Test 3: Agent Blocked**
```
1. Login as agent
2. Open ExpenseCreationScreen
✅ Shows "Access Denied" screen
✅ Shows "Your role: agent"
✅ "Go Back" button works
```

### **Test 4: Superagent Blocked**
```
1. Login as superagent
2. Open ExpenseCreationScreen
✅ Shows "Access Denied" screen
✅ Shows "Your role: superagent"
✅ Cannot create expenses
```

### **Test 5: No Role**
```
1. User without role field
2. Open ExpenseCreationScreen
✅ Shows "Access Denied" screen
✅ Defaults to no access
```

### **Test 6: Loading State**
```
1. Open ExpenseCreationScreen
2. Observe during role check
✅ Shows loading spinner
✅ Then shows appropriate screen
```

---

## 🎯 Why This Restriction?

### **Business Logic:**

**Technicians:**
- ✅ Work on-site
- ✅ Purchase equipment/supplies
- ✅ Need to track expenses
- ✅ Submit for boss approval

**Boss:**
- ✅ Makes large purchases
- ✅ Manages budgets
- ✅ Needs another boss to approve
- ✅ Can create and review

**Agents/Superagents:**
- ❌ Focus on user generation
- ❌ Don't handle physical expenses
- ❌ No need for expense creation
- ❌ Only revenue collection

---

## 🔗 Integration with Approval

### **Expense Approval (Boss Only):**

**All roles can:**
- ❌ **Not applicable** - Only boss can approve

**Only boss can:**
- ✅ View pending expenses
- ✅ Approve expenses (not own)
- ✅ Reject expenses (not own)

**Workflow:**
```
Technician creates expense
    ↓
Status: pending
    ↓
Boss reviews
    ↓
Boss approves/rejects
    ↓
Status: approved/rejected
```

---

## 📝 Code Implementation

### **Role Check Method:**
```dart
Future<void> _checkUserRole() async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _checkingRole = false;
        _hasAccess = false;
      });
      return;
    }
    
    // Get user role from Firestore
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(user.email)
        .get();
    
    if (userDoc.exists) {
      final role = userDoc.data()?['role'] as String?;
      setState(() {
        _userRole = role;
        // Only technician and boss
        _hasAccess = role == 'technician' || role == 'boss';
        _checkingRole = false;
      });
    } else {
      setState(() {
        _checkingRole = false;
        _hasAccess = false;
      });
    }
  } catch (e) {
    print('Error checking role: $e');
    setState(() {
      _checkingRole = false;
      _hasAccess = false;
    });
  }
}
```

### **Build Method:**
```dart
@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(...),
    body: _checkingRole
        ? const Center(child: CircularProgressIndicator())
        : !_hasAccess
            ? _buildAccessDenied()  // Show access denied
            : Form(...),  // Show expense form
  );
}
```

### **Access Denied Widget:**
```dart
Widget _buildAccessDenied() {
  return Center(
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.block, size: 80, color: Colors.red[300]),
        const SizedBox(height: 24),
        Text(
          'Access Denied',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.red[700],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Only Technicians and Boss can create expenses.',
          textAlign: TextAlign.center,
        ),
        if (_userRole != null)
          Container(
            child: Text('Your role: $_userRole'),
          ),
        ElevatedButton.icon(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back),
          label: const Text('Go Back'),
        ),
      ],
    ),
  );
}
```

---

## ✅ Summary

### **Access Control:**
- ✅ Technician role → Can create expenses
- ✅ Boss role → Can create expenses
- ❌ Agent role → Access denied
- ❌ Superagent role → Access denied
- ❌ Other roles → Access denied

### **User Experience:**
- ✅ Loading spinner during role check
- ✅ Clear "Access Denied" message
- ✅ Shows user's current role
- ✅ "Go Back" button for navigation
- ✅ No access to form for unauthorized users

### **Security:**
- ✅ Server-side role check (Firestore)
- ✅ Cannot bypass client-side
- ✅ Role stored in secure users collection
- ✅ Defaults to deny if no role found

**Expense creation restricted to Technician and Boss roles only!** 🔒✅
