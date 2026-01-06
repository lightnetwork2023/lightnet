# ✅ Dormant Sublocation Identification Feature

## 🎯 Purpose
Easily identify sublocations with **zero revenue** (dormant/inactive) to take action.

---

## 🚨 Dormant Definition
**Dormant Sublocation:** A sublocation with `totalRevenue == 0` for the selected time period.

---

## 📊 Three-Level Identification System

### **Level 1: Main Location Card - Quick Alert** ⚠️

**Immediate visibility on main screen:**

```
┌───────────────────────────────────┐
│ 🏆 #1 MBAGALA                    │
│ 🌳 5 sublocations  ⚠️ 2 dormant  │  ← Red warning!
│                            ⚙️     │
│ Revenue   | Payments | Last       │
│ 25.5M     | 350     | 1h ago     │
└───────────────────────────────────┘
```

**Features:**
- 🌳 Blue icon = Total sublocation count
- ⚠️ Red icon = Dormant sublocation count
- Only shows if there are dormant sublocations
- Immediate alert without opening details

---

### **Level 2: Details Modal - Sorted List** 📋

**Tap location → Sublocations sorted by activity:**

```
┌─────────────────────────────────────┐
│ MBAGALA                      ✕     │
│ Includes 5 sublocations            │
├─────────────────────────────────────┤
│ 🌳 Sublocation Breakdown           │
│                                     │
│ ✅ ACTIVE SUBLOCATIONS:            │
│                                     │
│ ┌─────────────────────────────┐   │
│ │ MBAGALA-A      [Sub]        │   │ ← Active (has revenue)
│ │ Revenue: 15.5M              │   │
│ │ Payments: 200               │   │
│ └─────────────────────────────┘   │
│                                     │
│ ┌─────────────────────────────┐   │
│ │ MBAGALA-B      [Sub]        │   │
│ │ Revenue: 10.0M              │   │
│ │ Payments: 150               │   │
│ └─────────────────────────────┘   │
│                                     │
│ ❌ DORMANT SUBLOCATIONS:           │
│                                     │
│ ┌─────────────────────────────┐   │
│ │ MBAGALA-C  [Sub] ⚠️ Dormant │   │ ← Red background!
│ │ Revenue: 0                  │   │ ← Red text!
│ │ Payments: 0                 │   │ ← Red border!
│ └─────────────────────────────┘   │
│                                     │
│ ┌─────────────────────────────┐   │
│ │ MBAGALA-D  [Sub] ⚠️ Dormant │   │
│ │ Revenue: 0                  │   │
│ │ Payments: 0                 │   │
│ └─────────────────────────────┘   │
└─────────────────────────────────────┘
```

**Features:**
- ✅ **Active sublocations at top** (sorted by revenue)
- ❌ **Dormant sublocations at bottom**
- Red background for dormant
- Red border (thicker) for dormant
- Red "⚠️ Dormant" badge
- Location name in red color

---

### **Level 3: Visual Styling** 🎨

**Active Sublocation:**
```
┌─────────────────────────────┐
│ MBAGALA-A      [Sub]        │  ← Normal styling
│ Revenue: 15.5M              │  ← Black text
│ Payments: 200               │  ← Gray background
└─────────────────────────────┘  ← Gray border
```

**Dormant Sublocation:**
```
┌─────────────────────────────┐
│ MBAGALA-C  [Sub] ⚠️ Dormant │  ← Red text
│ Revenue: 0                  │  ← Red background
│ Payments: 0                 │  ← Red border (thick)
└─────────────────────────────┘  ← Stands out!
```

---

## 🔍 How It Works

### **1. Dormant Detection:**
```dart
// Check if sublocation is dormant
final isDormant = sublocation.totalRevenue == 0;
```

### **2. Count Dormant Sublocations:**
```dart
// On main location card
final sublocations = _locationStats
    .where((s) => s.parentLocation == mainLocation.locationId)
    .toList();

final sublocationCount = sublocations.length;
final dormantCount = sublocations.where((s) => s.totalRevenue == 0).length;
```

### **3. Display Dormant Alert:**
```dart
// Show warning if there are dormant sublocations
if (dormantCount > 0)
  Row(
    children: [
      Icon(Icons.warning_rounded, color: Colors.red[700]),
      Text('$dormantCount dormant', 
        style: TextStyle(color: Colors.red[700], fontWeight: bold)
      ),
    ],
  )
```

### **4. Sort by Activity:**
```dart
// Sort: active first, then dormant
sublocations.sort((a, b) {
  final aActive = a.totalRevenue > 0 ? 1 : 0;
  final bActive = b.totalRevenue > 0 ? 1 : 0;
  if (aActive != bActive) return bActive.compareTo(aActive);
  return b.totalRevenue.compareTo(a.totalRevenue); // Then by revenue
});
```

### **5. Apply Dormant Styling:**
```dart
// Visual indicators for dormant
Container(
  decoration: BoxDecoration(
    color: isDormant ? Colors.red[50] : Colors.grey[50],
    border: Border.all(
      color: isDormant ? Colors.red[200]! : Colors.grey[200]!,
      width: isDormant ? 1.5 : 1,
    ),
  ),
  child: Column(
    children: [
      Text(
        sublocation.name,
        style: TextStyle(
          color: isDormant ? Colors.red[900] : Colors.black,
        ),
      ),
      if (isDormant)
        Container(
          child: Row(
            children: [
              Icon(Icons.warning_rounded, color: Colors.red[800]),
              Text('Dormant', style: TextStyle(color: Colors.red[800])),
            ],
          ),
        ),
    ],
  ),
)
```

---

## 📱 User Experience Flow

### **Step 1: Scan Main Screen**
```
Quickly see which main locations have dormant sublocations:

🏆 MBAGALA
   🌳 5 sublocations  ⚠️ 2 dormant  ← Needs attention!

🥈 KINONDONI
   🌳 3 sublocations  ⚠️ 1 dormant  ← Needs attention!

🥉 TEMEKE
   🌳 4 sublocations                 ← All active, good!
```

### **Step 2: Tap for Details**
```
Tap on MBAGALA to see breakdown:
- Active sublocations at top (green zone)
- Dormant sublocations at bottom (red zone)
- Clear visual separation
```

### **Step 3: Identify Issues**
```
See exactly which sublocations are dormant:
- MBAGALA-C: ⚠️ Dormant - 0 revenue
- MBAGALA-D: ⚠️ Dormant - 0 revenue

Take action:
- Check if equipment is working
- Verify network connectivity
- Consider reassignment
- Investigate why no activity
```

---

## 🎯 Use Cases

### **Use Case 1: Daily Check**
```
Open Location Analytics
↓
Scan main cards for red ⚠️ warnings
↓
Tap locations with dormant warnings
↓
Review dormant sublocations
↓
Take corrective action
```

### **Use Case 2: Time Period Analysis**
```
Select "This Month" filter
↓
Check which sublocations were dormant all month
↓
Decide if they should be reassigned or deactivated
```

### **Use Case 3: New Sublocation Setup**
```
Created new sublocation yesterday
↓
Select "Last 24 Hours" filter
↓
Check if it appears as dormant
↓
If dormant: troubleshoot setup
If active: setup successful!
```

### **Use Case 4: Performance Optimization**
```
Main location has 10 sublocations
↓
5 are dormant (shown in red)
↓
Consider consolidating or reassigning
↓
Optimize resource allocation
```

---

## 🔍 Visual Indicators Summary

| Element | Active | Dormant |
|---------|--------|---------|
| **Background** | Gray (50) | Red (50) |
| **Border** | Gray 1px | Red 1.5px |
| **Text Color** | Black | Red (900) |
| **Badge** | "Sub" only | "Sub" + "⚠️ Dormant" |
| **Card Alert** | None | ⚠️ X dormant |
| **Sort Order** | First | Last |

---

## 📊 Example Scenarios

### **Scenario 1: Healthy Location**
```
MBAGALA - TZS 50.0M
🌳 5 sublocations
(No dormant warning)

All sublocations active and generating revenue ✅
```

### **Scenario 2: Problem Location**
```
KINONDONI - TZS 15.0M
🌳 8 sublocations  ⚠️ 5 dormant

More dormant than active - needs investigation! ⚠️
```

### **Scenario 3: New Setup**
```
DODOMA - TZS 0
🌳 3 sublocations  ⚠️ 3 dormant

All dormant - just set up, no activity yet 🆕
```

### **Scenario 4: Partial Activity**
```
MWANZA - TZS 20.0M
🌳 4 sublocations  ⚠️ 1 dormant

Mostly active, one needs attention 📍
```

---

## ✅ Benefits

### **Business Value:**
- ✅ **Immediate identification** of non-performing sublocations
- ✅ **Proactive management** - catch issues early
- ✅ **Resource optimization** - reassign or fix dormant locations
- ✅ **Performance monitoring** - track which sublocations work

### **User Experience:**
- ✅ **Three-level visibility** - card, list, detail
- ✅ **Visual hierarchy** - active vs dormant clear
- ✅ **No searching needed** - red warnings stand out
- ✅ **Actionable insights** - know exactly what needs attention

### **Operational:**
- ✅ **Quick scans** - see all dormant at a glance
- ✅ **Time period analysis** - check different periods
- ✅ **Sorted display** - prioritizes active locations
- ✅ **Clear indicators** - no confusion about status

---

## 🧪 Testing Checklist

**Test 1: Dormant Detection**
```
✓ Sublocation with 0 revenue shows as dormant
✓ Sublocation with any revenue shows as active
✓ Correct count on main location card
```

**Test 2: Visual Indicators**
```
✓ Red background on dormant sublocations
✓ Red border (thicker) on dormant
✓ "⚠️ Dormant" badge displays
✓ Warning icon on main card
```

**Test 3: Sorting**
```
✓ Active sublocations appear first
✓ Dormant sublocations appear last
✓ Within active: sorted by revenue (high to low)
```

**Test 4: Time Periods**
```
✓ Dormant status changes with filter
✓ "Last 24 Hours" shows recent dormant
✓ "This Month" shows monthly dormant
```

**Test 5: Edge Cases**
```
✓ All sublocations active - no warning shown
✓ All sublocations dormant - shows count
✓ No sublocations - no warning section
✓ Single sublocation - proper count display
```

---

## 🎯 Summary

**Implemented Features:**
1. ✅ Dormant count on main location cards
2. ✅ Red warning indicator with icon
3. ✅ Sorted sublocation list (active first)
4. ✅ Visual styling for dormant sublocations
5. ✅ "Dormant" badge on inactive sublocations

**Identification Methods:**
- **Quick:** Red warning on card
- **Detailed:** Sorted list in modal
- **Visual:** Red background, border, badges

**User Actions Enabled:**
- Spot dormant sublocations instantly
- Investigate issues quickly
- Make informed decisions
- Optimize location performance

**Business Impact:**
- Better resource management
- Proactive problem solving
- Performance optimization
- Data-driven decisions

**Ready to identify and manage dormant sublocations!** 🎯
