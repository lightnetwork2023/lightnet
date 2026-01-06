# 🔧 Location Reassignment Feature

## ✅ Implementation Complete

Added the ability to reassign locations between **Main Location** and **Sublocation** types, including parent selection.

---

## 🎯 Features

### **1. Settings Button on Each Location Card**
- ⚙️ Settings icon on every location card
- Opens reassignment dialog
- Color: Primary theme color

### **2. Reassignment Dialog**
- Shows current location name
- Two radio options:
  - **Main Location** - Independent location
  - **Sublocation** - Under a main location
- Parent location dropdown (if sublocation selected)
- Save and Cancel buttons

### **3. Parent Location Selection**
- Dropdown with all main locations
- Excludes the current location itself
- Warning if no main locations available
- Required for sublocation type

### **4. Firestore Update**
- Updates `locations/{locationId}` document
- Sets `parent_location` and `type` fields
- Success/error notifications
- Automatic data reload after update

---

## 🎨 UI Components

### **Location Card with Settings Button:**
```dart
Row(
  children: [
    // Rank badge
    Container(rank),
    
    // Location name and info
    Expanded(
      child: Column(
        children: [
          Text(locationName),
          if (sublocation) Badge('Sub'),
          if (hasParent) Text('Parent: X'),
        ],
      ),
    ),
    
    // Settings button ⚙️
    IconButton(
      icon: Icons.settings,
      onPressed: _showLocationReassignDialog,
    ),
  ],
)
```

### **Reassignment Dialog:**
```
┌─────────────────────────────────────┐
│ 📍 Reassign Location               │
├─────────────────────────────────────┤
│ MBAGALA-A                           │
│                                     │
│ Location Type:                      │
│ ○ Main Location                     │
│   Independent location              │
│ ● Sublocation                       │
│   Under a main location             │
│                                     │
│ Parent Location:                    │
│ ┌─────────────────────────────┐    │
│ │ MBAGALA                ▼    │    │
│ └─────────────────────────────┘    │
│                                     │
│         [Cancel]  [Save]            │
└─────────────────────────────────────┘
```

---

## 🔧 How It Works

### **1. User Interaction:**
```
Tap ⚙️ settings icon on location card
  ↓
Dialog opens with current configuration
  ↓
User selects location type:
  - Main Location (no parent needed)
  - Sublocation (parent required)
  ↓
If sublocation: Select parent from dropdown
  ↓
Tap Save
  ↓
Firestore updates
  ↓
Success message shown
  ↓
Screen reloads with updated data
```

### **2. Firestore Update:**

**Main Location:**
```dart
locations/MBAGALA {
  parent_location: null,
  type: "main",
  metadata: {...}
}
```

**Sublocation:**
```dart
locations/MBAGALA-A {
  parent_location: "MBAGALA",
  type: "sublocation",
  metadata: {...}
}
```

### **3. Validation:**
- Can't select itself as parent
- Must select parent if type is sublocation
- Save button disabled until valid configuration
- Handles case when no main locations exist

---

## 📊 Usage Examples

### **Example 1: Convert Main to Sublocation**
```
Current: KINONDONI (Main Location)
Goal: Make it sublocation of MBAGALA

1. Tap ⚙️ on KINONDONI card
2. Dialog shows: ○ Main (selected)
3. Select: ● Sublocation
4. Dropdown appears: "Select parent location"
5. Select: MBAGALA
6. Tap Save
7. Success: "KINONDONI → sublocation of MBAGALA"
8. Card updates with "Sub" badge and "Parent: MBAGALA"
```

### **Example 2: Convert Sublocation to Main**
```
Current: MBAGALA-A (Sublocation of MBAGALA)
Goal: Make it independent main location

1. Tap ⚙️ on MBAGALA-A card
2. Dialog shows: ● Sublocation (selected)
                  Parent: MBAGALA
3. Select: ○ Main Location
4. Parent dropdown disappears
5. Tap Save
6. Success: "MBAGALA-A → main location"
7. "Sub" badge removed, no parent shown
```

### **Example 3: Change Parent Location**
```
Current: BRANCH-1 (Sublocation of MBAGALA)
Goal: Change parent to KINONDONI

1. Tap ⚙️ on BRANCH-1 card
2. Dialog shows: ● Sublocation (selected)
                  Parent: MBAGALA
3. Keep: ● Sublocation
4. Change dropdown: KINONDONI
5. Tap Save
6. Success: "BRANCH-1 → sublocation of KINONDONI"
7. Parent text updates: "Parent: KINONDONI"
```

---

## 🎯 Code Implementation

### **Settings Button Added:**
```dart
// In location card Row
IconButton(
  icon: const Icon(Icons.settings, size: 20),
  color: AppTheme.primaryColor,
  onPressed: () => _showLocationReassignDialog(stats),
  tooltip: 'Reassign Location',
)
```

### **Reassignment Dialog:**
```dart
void _showLocationReassignDialog(LocationStats stats) {
  String locationType = stats.parentLocation == null ? 'main' : 'sublocation';
  String? selectedParent = stats.parentLocation;
  
  // Get available main locations
  final mainLocations = _locationStats
      .where((loc) => loc.parentLocation == null && 
                      loc.locationId != stats.locationId)
      .map((loc) => loc.locationId)
      .toList();

  showDialog(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) {
        return AlertDialog(
          title: Text('Reassign Location'),
          content: Column(
            children: [
              Text(stats.locationId),
              
              // Radio buttons for type
              RadioListTile(
                title: Text('Main Location'),
                value: 'main',
                groupValue: locationType,
                onChanged: (value) {
                  setDialogState(() {
                    locationType = value!;
                    selectedParent = null;
                  });
                },
              ),
              RadioListTile(
                title: Text('Sublocation'),
                value: 'sublocation',
                groupValue: locationType,
                onChanged: (value) {
                  setDialogState(() {
                    locationType = value!;
                  });
                },
              ),
              
              // Dropdown for parent (if sublocation)
              if (locationType == 'sublocation')
                DropdownButton<String>(
                  value: selectedParent,
                  hint: Text('Select parent location'),
                  items: mainLocations.map((loc) =>
                    DropdownMenuItem(value: loc, child: Text(loc))
                  ).toList(),
                  onChanged: (value) {
                    setDialogState(() {
                      selectedParent = value;
                    });
                  },
                ),
            ],
          ),
          actions: [
            TextButton(child: Text('Cancel'), onPressed: () => Navigator.pop(context)),
            ElevatedButton(
              child: Text('Save'),
              onPressed: () {
                Navigator.pop(context);
                _updateLocationAssignment(stats.locationId, locationType, selectedParent);
              },
            ),
          ],
        );
      },
    ),
  );
}
```

### **Firestore Update:**
```dart
Future<void> _updateLocationAssignment(
  String locationId,
  String locationType,
  String? parentLocation,
) async {
  final locationDoc = _firestore.collection('locations').doc(locationId);
  
  if (locationType == 'main') {
    await locationDoc.set({
      'parent_location': null,
      'type': 'main',
    }, SetOptions(merge: true));
  } else {
    await locationDoc.set({
      'parent_location': parentLocation,
      'type': 'sublocation',
    }, SetOptions(merge: true));
  }
  
  // Show success notification
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Location updated successfully!')),
  );
  
  // Reload data
  _loadLocationAnalytics();
}
```

---

## ⚡ Validation & Error Handling

### **Validation Rules:**
1. ✅ Can't select itself as parent
2. ✅ Must select parent if type is sublocation (with main locations available)
3. ✅ Save button disabled until valid configuration
4. ✅ Warning shown if no main locations exist

### **Error Handling:**
```dart
try {
  await locationDoc.set({...});
  // Success notification
} catch (e) {
  // Error notification
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text('Error: ${e.toString()}'),
      backgroundColor: Colors.red,
    ),
  );
}
```

### **Edge Cases:**
- **No main locations available** → Warning message shown
- **Last main location** → Can still convert to sublocation
- **Firestore error** → Red error notification
- **Network issues** → Error caught and displayed

---

## 🧪 Testing Scenarios

### **Test 1: Convert Main to Sublocation**
```
1. Open Location Analytics
2. Find MBAGALA (main location)
3. Tap ⚙️ settings button
4. Verify: "Main Location" is selected
5. Select: "Sublocation"
6. Verify: Parent dropdown appears
7. Select parent: KINONDONI
8. Tap Save
9. Verify: Success message appears
10. Verify: Card shows "Sub" badge
11. Verify: Shows "Parent: KINONDONI"
```

### **Test 2: Convert Sublocation to Main**
```
1. Find MBAGALA-A (sublocation)
2. Tap ⚙️ settings button
3. Verify: "Sublocation" is selected
4. Verify: Parent shown in dropdown
5. Select: "Main Location"
6. Verify: Parent dropdown disappears
7. Tap Save
8. Verify: Success message appears
9. Verify: "Sub" badge removed
10. Verify: No parent text shown
```

### **Test 3: Change Parent**
```
1. Find BRANCH-1 (sublocation of MBAGALA)
2. Tap ⚙️ settings button
3. Keep: "Sublocation" selected
4. Change dropdown from MBAGALA to KINONDONI
5. Tap Save
6. Verify: Success message shows new parent
7. Verify: Card shows "Parent: KINONDONI"
```

### **Test 4: No Main Locations**
```
1. Convert all locations to sublocations (edge case)
2. Try to reassign last location
3. Verify: Warning message shown
4. Verify: "No main locations available"
5. Can only select "Main Location" type
```

### **Test 5: Validation**
```
1. Select "Sublocation" type
2. Don't select parent
3. Verify: Save button is disabled
4. Select a parent
5. Verify: Save button is enabled
```

---

## 📱 User Flow

```
┌─────────────────────────────────────┐
│ Location Analytics Screen           │
│                                     │
│ 🏆 #1 MBAGALA          ⚙️           │
│ 🥈 #2 MBAGALA-A [Sub]  ⚙️           │
│ 🥉 #3 KINONDONI        ⚙️           │
└─────────────────────────────────────┘
              │
              │ Tap ⚙️ on MBAGALA-A
              ▼
┌─────────────────────────────────────┐
│ 📍 Reassign Location                │
│ MBAGALA-A                           │
│                                     │
│ ○ Main Location                     │
│ ● Sublocation                       │
│                                     │
│ Parent: [MBAGALA ▼]                 │
│                                     │
│         [Cancel]  [Save]            │
└─────────────────────────────────────┘
              │
              │ Select: ○ Main Location
              ▼
┌─────────────────────────────────────┐
│ 📍 Reassign Location                │
│ MBAGALA-A                           │
│                                     │
│ ● Main Location                     │
│ ○ Sublocation                       │
│                                     │
│ (No parent selection needed)        │
│                                     │
│         [Cancel]  [Save]            │
└─────────────────────────────────────┘
              │
              │ Tap Save
              ▼
┌─────────────────────────────────────┐
│ ⏳ Updating location...              │
└─────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│ ✅ Successfully updated MBAGALA-A   │
│    to main location                 │
└─────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────────────┐
│ Location Analytics Screen           │
│ (Reloaded)                          │
│                                     │
│ 🏆 #1 MBAGALA          ⚙️           │
│ 🥈 #2 MBAGALA-A        ⚙️   ← Main! │
│ 🥉 #3 KINONDONI        ⚙️           │
└─────────────────────────────────────┘
```

---

## ✅ Summary

**Added:**
- ✅ Settings button on each location card
- ✅ Reassignment dialog with type selection
- ✅ Parent location dropdown for sublocations
- ✅ Firestore update with merge
- ✅ Success/error notifications
- ✅ Automatic screen reload
- ✅ Validation and edge case handling

**Features:**
- ✅ Convert main ↔ sublocation
- ✅ Change parent location
- ✅ Visual feedback (loading, success, error)
- ✅ Dynamic UI based on selection
- ✅ List of available main locations

**User Experience:**
- ✅ One-tap access to settings
- ✅ Clear visual dialog
- ✅ Intuitive radio buttons
- ✅ Dropdown for parent selection
- ✅ Immediate visual updates

**Ready to use!** 🚀
