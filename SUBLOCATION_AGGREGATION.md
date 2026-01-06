# ✅ Sublocation Aggregation Feature

## 🎯 Main Locations Now Include Sublocation Totals

Main locations now display **combined totals** including all their sublocations' revenue and payments.

---

## 📊 How It Works

### **Aggregation Logic:**

```dart
// After building initial stats, aggregate sublocation data
for (var mainLocation in stats.where((s) => s.type == 'main')) {
  // Find all sublocations of this main location
  final sublocations = stats.where((s) => s.parentLocation == mainLocation.locationId);
  
  double sublocationRevenue = 0;
  int sublocationPayments = 0;
  Timestamp? latestPayment = mainLocation.lastPaymentAt;
  
  // Aggregate sublocation data
  for (var sublocation in sublocations) {
    sublocationRevenue += sublocation.totalRevenue;
    sublocationPayments += sublocation.paymentCount;
    
    // Track latest payment across all sublocations
    if (sublocation.lastPaymentAt != null) {
      if (latestPayment == null || 
          sublocation.lastPaymentAt!.compareTo(latestPayment) > 0) {
        latestPayment = sublocation.lastPaymentAt;
      }
    }
  }
  
  // Update main location with combined totals
  stats[index] = LocationStats(
    locationId: mainLocation.locationId,
    totalRevenue: mainLocation.totalRevenue + sublocationRevenue,
    paymentCount: mainLocation.paymentCount + sublocationPayments,
    lastPaymentAt: latestPayment,
    parentLocation: mainLocation.parentLocation,
    type: mainLocation.type,
  );
}
```

---

## 📱 Visual Display

### **Location Card with Sublocations:**

**Before:**
```
🏆 #1 MBAGALA
   💰 Revenue: TZS 100,000
   📋 Payments: 50
```

**After (with 3 sublocations):**
```
🏆 #1 MBAGALA
   🌳 3 sublocations
   💰 Revenue: TZS 500,000    ← Includes sublocations!
   📋 Payments: 250           ← Includes sublocations!
```

### **Sublocation Card (unchanged):**
```
📍 #4 MBAGALA-A [Sub]
   Parent: MBAGALA
   💰 Revenue: TZS 150,000    ← Individual revenue
   📋 Payments: 75            ← Individual payments
```

---

## 🔍 Details Modal with Breakdown

### **Main Location Details:**

**When you tap on MBAGALA:**
```
┌─────────────────────────────────────┐
│ MBAGALA                      ✕     │
│ Includes 3 sublocations            │
├─────────────────────────────────────┤
│ Total Revenue: TZS 500,000         │
│ Total Payments: 250                │
│ Average per Payment: TZS 2,000     │
│ Last Payment: 2024-11-12 10:30     │
│ Type: main                          │
│                                     │
│ ─────────────────────────────       │
│                                     │
│ 🌳 Sublocation Breakdown           │
│                                     │
│ ┌─────────────────────────────┐   │
│ │ MBAGALA-A          [Sub]    │   │
│ │ Revenue: TZS 150,000        │   │
│ │ Payments: 75                │   │
│ └─────────────────────────────┘   │
│                                     │
│ ┌─────────────────────────────┐   │
│ │ MBAGALA-B          [Sub]    │   │
│ │ Revenue: TZS 200,000        │   │
│ │ Payments: 100               │   │
│ └─────────────────────────────┘   │
│                                     │
│ ┌─────────────────────────────┐   │
│ │ MBAGALA-C          [Sub]    │   │
│ │ Revenue: TZS 50,000         │   │
│ │ Payments: 25                │   │
│ └─────────────────────────────┘   │
│                                     │
│ Total from main: TZS 100,000       │
│ Total from subs: TZS 400,000       │
│ Combined total: TZS 500,000        │
└─────────────────────────────────────┘
```

### **Sublocation Details (unchanged):**
```
┌─────────────────────────────────────┐
│ MBAGALA-A                    ✕     │
├─────────────────────────────────────┤
│ Total Revenue: TZS 150,000         │
│ Total Payments: 75                 │
│ Average per Payment: TZS 2,000     │
│ Last Payment: 2024-11-12 09:45     │
│ Parent Location: MBAGALA           │
│ Type: sublocation                  │
└─────────────────────────────────────┘
```

---

## 🎯 Example Scenarios

### **Scenario 1: Main Location with Sublocations**

**Firestore Data:**
```javascript
// Payments for selected period
payments: [
  { location: "MBAGALA", amount: 100000 },      // Main direct
  { location: "MBAGALA-A", amount: 150000 },    // Sublocation
  { location: "MBAGALA-B", amount: 200000 },    // Sublocation
  { location: "MBAGALA-C", amount: 50000 },     // Sublocation
]

// Location metadata
locations/MBAGALA { type: "main" }
locations/MBAGALA-A { type: "sublocation", parent_location: "MBAGALA" }
locations/MBAGALA-B { type: "sublocation", parent_location: "MBAGALA" }
locations/MBAGALA-C { type: "sublocation", parent_location: "MBAGALA" }
```

**Display:**
```
🏆 #1 MBAGALA
   🌳 3 sublocations
   💰 Revenue: TZS 500,000
   ↳ Main: TZS 100,000
   ↳ Subs: TZS 400,000
   📋 Payments: 4

📍 #2 MBAGALA-A [Sub]
   Parent: MBAGALA
   💰 Revenue: TZS 150,000    ← Still shows individual
   📋 Payments: 1

📍 #3 MBAGALA-B [Sub]
   Parent: MBAGALA
   💰 Revenue: TZS 200,000
   📋 Payments: 1

📍 #4 MBAGALA-C [Sub]
   Parent: MBAGALA
   💰 Revenue: TZS 50,000
   📋 Payments: 1
```

### **Scenario 2: Multiple Main Locations**

**Data:**
```
MBAGALA (main): TZS 100,000
  ├─ MBAGALA-A (sub): TZS 150,000
  └─ MBAGALA-B (sub): TZS 200,000
Total shown: TZS 450,000

KINONDONI (main): TZS 50,000
  └─ KINONDONI-A (sub): TZS 75,000
Total shown: TZS 125,000

TEMEKE (main): TZS 300,000
  (no sublocations)
Total shown: TZS 300,000
```

**Ranking:**
```
🏆 #1 MBAGALA - TZS 450,000 (3 sublocations)
🥈 #2 TEMEKE - TZS 300,000
🥉 #3 KINONDONI - TZS 125,000 (1 sublocation)
📍 #4 MBAGALA-B [Sub] - TZS 200,000
📍 #5 MBAGALA-A [Sub] - TZS 150,000
📍 #6 KINONDONI-A [Sub] - TZS 75,000
```

### **Scenario 3: Main with No Sublocations**

**Data:**
```
DODOMA (main): TZS 200,000
(no sublocations)
```

**Display:**
```
🥈 #2 DODOMA
   💰 Revenue: TZS 200,000    ← Only its own revenue
   📋 Payments: 100

No sublocation breakdown shown in details.
```

---

## 🎨 UI Features

### **1. Location Card Indicator:**
```dart
if (sublocationCount > 0)
  Row(
    children: [
      Icon(Icons.account_tree, size: 12, color: Colors.blue[700]),
      SizedBox(width: 4),
      Text(
        '$sublocationCount sublocation${sublocationCount > 1 ? 's' : ''}',
        style: TextStyle(
          fontSize: 11,
          color: Colors.blue[700],
          fontWeight: FontWeight.w500,
        ),
      ),
    ],
  )
```

**Shows:**
- 🌳 1 sublocation
- 🌳 3 sublocations

### **2. Details Modal Header:**
```dart
if (sublocations.isNotEmpty)
  Text(
    'Includes ${sublocations.length} sublocation${sublocations.length > 1 ? 's' : ''}',
    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
  )
```

### **3. Sublocation Breakdown Section:**
```dart
if (sublocations.isNotEmpty) ...[
  Divider(),
  Row(
    children: [
      Icon(Icons.account_tree, color: AppTheme.primaryColor),
      Text('Sublocation Breakdown'),
    ],
  ),
  // List of sublocation cards with individual stats
]
```

---

## 📊 Summary Header Impact

**Summary Header Totals:**
```
┌─────────────────────────────────────┐
│ 💰 Total Revenue                   │
│    TZS 1,450,000                   │
│    ↑ Includes all locations        │
│                                     │
│ 📋 Total Payments                  │
│    354                              │
│    ↑ Includes all locations        │
│                                     │
│ 📍 Active Locations                │
│    6                                │
│    ↑ 3 main + 3 sublocations       │
└─────────────────────────────────────┘
```

**Note:** Summary totals include ALL payments from all locations (main and sub) without double-counting.

---

## 🔍 Data Flow

### **Step 1: Collect Payment Data**
```
Payments Collection → Group by location
{
  "MBAGALA": {revenue: 100000, count: 1},
  "MBAGALA-A": {revenue: 150000, count: 1},
  "MBAGALA-B": {revenue: 200000, count: 1},
  "KINONDONI": {revenue: 50000, count: 1}
}
```

### **Step 2: Create Initial Stats**
```
LocationStats[
  {id: "MBAGALA", revenue: 100000, type: "main"},
  {id: "MBAGALA-A", revenue: 150000, type: "sublocation", parent: "MBAGALA"},
  {id: "MBAGALA-B", revenue: 200000, type: "sublocation", parent: "MBAGALA"},
  {id: "KINONDONI", revenue: 50000, type: "main"}
]
```

### **Step 3: Aggregate Sublocations**
```
For MBAGALA (main):
  Find: MBAGALA-A, MBAGALA-B
  Aggregate: 150000 + 200000 = 350000
  Update: MBAGALA.revenue = 100000 + 350000 = 450000
  
For KINONDONI (main):
  Find: (none)
  No update needed
```

### **Step 4: Final Stats**
```
LocationStats[
  {id: "MBAGALA", revenue: 450000, type: "main"},        ← Updated!
  {id: "MBAGALA-A", revenue: 150000, type: "sublocation", parent: "MBAGALA"},
  {id: "MBAGALA-B", revenue: 200000, type: "sublocation", parent: "MBAGALA"},
  {id: "KINONDONI", revenue: 50000, type: "main"}
]
```

### **Step 5: Sort & Display**
```
Sorted by revenue:
1. MBAGALA - TZS 450,000
2. MBAGALA-B - TZS 200,000
3. MBAGALA-A - TZS 150,000
4. KINONDONI - TZS 50,000
```

---

## ✅ Key Features

**Implemented:**
- ✅ Main locations show combined totals (own + sublocations)
- ✅ Sublocation indicator on main location cards
- ✅ Detailed breakdown in modal
- ✅ Individual sublocation stats preserved
- ✅ Latest payment tracked across sublocations
- ✅ Summary header includes all locations

**Benefits:**
- ✅ See total performance per main location
- ✅ Compare main locations with all their branches
- ✅ Drill down into individual sublocation performance
- ✅ Understand location hierarchy at a glance
- ✅ Better business insights and decision making

**User Experience:**
- ✅ Clear visual indicators (🌳 icon)
- ✅ Sublocation count shown on cards
- ✅ Detailed breakdown in modal
- ✅ Individual stats still accessible
- ✅ No double counting in summary

**Ready to use!** 🚀
