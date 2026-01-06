# ✅ Location Hierarchy in User Generation

## 🎯 Feature
When adding a new location in the User Generation screen, you can now specify:
- **Location Type:** Main Location or Sublocation
- **Parent Location:** If it's a sublocation, select which main location it belongs to

---

## 📱 User Interface

### **Add New Location Section:**

```
┌─────────────────────────────────────┐
│ Add New Location                    │
│ [Text Input Field]            [+]   │
│                                     │
│ ○ Main Location  ● Sublocation     │ ← Radio buttons
│                                     │
│ Select Parent Location              │ ← Shows only if Sublocation
│ [Dropdown: MBAGALA ▼]              │
│ ⓘ Choose which main location        │
│   this sublocation belongs to       │
└─────────────────────────────────────┘
```

---

## 🔧 How It Works

### **Step 1: Enter Location Name**
```
Type: "MBAGALA-A"
```

### **Step 2: Select Location Type**
**Option A: Main Location**
- Radio button: ● Main Location
- No parent selection needed
- Location will be independent

**Option B: Sublocation**
- Radio button: ● Sublocation
- Parent dropdown appears
- Must select a parent location

### **Step 3: Select Parent (if Sublocation)**
```
Dropdown shows:
- MBAGALA
- KINONDONI  
- TEMEKE
- ...

Select: MBAGALA
```

### **Step 4: Add Location**
Click [+] button
→ Location created with hierarchy!

---

## 📊 Examples

### **Example 1: Creating a Main Location**

```
Input:
├─ Location Name: "DODOMA"
├─ Type: ● Main Location
└─ Parent: (not shown)

Result in Firestore:
locations/DODOMA {
  type: "main"
}
```

### **Example 2: Creating a Sublocation**

```
Input:
├─ Location Name: "MBAGALA-A"
├─ Type: ● Sublocation
└─ Parent: "MBAGALA"

Result in Firestore:
locations/MBAGALA-A {
  type: "sublocation",
  parent_location: "MBAGALA"
}
```

### **Example 3: Multiple Sublocations**

```
Create:
1. MBAGALA (main)
2. MBAGALA-A (sublocation of MBAGALA)
3. MBAGALA-B (sublocation of MBAGALA)
4. MBAGALA-C (sublocation of MBAGALA)

Result Hierarchy:
MBAGALA (main)
  ├─ MBAGALA-A
  ├─ MBAGALA-B
  └─ MBAGALA-C
```

---

## 🎨 UI States

### **State 1: Main Location Selected (Default)**

```
┌─────────────────────────────────────┐
│ Add New Location                    │
│ [DODOMA____________]          [+]   │
│                                     │
│ ● Main Location  ○ Sublocation     │
│                                     │
│ (No parent dropdown shown)          │
└─────────────────────────────────────┘
```

### **State 2: Sublocation Selected**

```
┌─────────────────────────────────────┐
│ Add New Location                    │
│ [MBAGALA-A_________]          [+]   │
│                                     │
│ ○ Main Location  ● Sublocation     │
│                                     │
│ Select Parent Location              │
│ [MBAGALA ▼]                        │
│ ⓘ Choose which main location        │
│   this sublocation belongs to       │
└─────────────────────────────────────┘
```

### **State 3: No Main Locations Available**

```
┌─────────────────────────────────────┐
│ Add New Location                    │
│ [MBAGALA-A_________]          [+]   │
│                                     │
│ ○ Main Location  ● Sublocation     │
│                                     │
│ Select Parent Location              │
│ [(empty dropdown)]                  │
│                                     │
│ ⚠️ No main locations available.     │
│   Create a main location first.     │
└─────────────────────────────────────┘
```

---

## ✅ Validation

### **Main Location:**
- ✅ Location name required
- ✅ No parent needed
- ✅ Auto-sets type: "main"

### **Sublocation:**
- ✅ Location name required
- ✅ Parent location required
- ✅ Must select from dropdown
- ✅ Auto-sets type: "sublocation"
- ⚠️ Error if no parent selected

---

## 🔄 Workflow

### **Creating Main Location:**
```
1. Enter location name
2. Keep "Main Location" selected (default)
3. Click [+]
4. ✅ "Location added"
5. Fields reset
```

### **Creating Sublocation:**
```
1. Enter location name
2. Select "Sublocation" radio
3. Parent dropdown appears
4. Select parent from dropdown
5. Click [+]
6. ✅ "Location added"
7. Fields reset (back to Main Location)
```

---

## 💾 Firestore Data Structure

### **Main Location Document:**
```javascript
// Collection: locations
// Document ID: MBAGALA

{
  type: "main"
}
```

### **Sublocation Document:**
```javascript
// Collection: locations  
// Document ID: MBAGALA-A

{
  type: "sublocation",
  parent_location: "MBAGALA"
}
```

### **Empty/Legacy Location (backward compatible):**
```javascript
// Collection: locations
// Document ID: LEGACY_LOCATION

{
  // No type field (treated as main/standalone)
}
```

---

## 🧪 Testing Scenarios

### **Test 1: Create Main Location**
```
Input:
- Name: "DODOMA"
- Type: Main Location

Expected:
✅ Location created
✅ Type: "main"
✅ No parent_location field
✅ Appears in Location Analytics
```

### **Test 2: Create Sublocation**
```
Input:
- Name: "DODOMA-A"
- Type: Sublocation
- Parent: "DODOMA"

Expected:
✅ Location created
✅ Type: "sublocation"
✅ parent_location: "DODOMA"
✅ Aggregated into DODOMA in analytics
```

### **Test 3: Missing Parent**
```
Input:
- Name: "DODOMA-B"
- Type: Sublocation
- Parent: (not selected)

Expected:
❌ Validation error
"Please select a parent location"
```

### **Test 4: Switch Type**
```
Actions:
1. Select Sublocation → parent dropdown appears
2. Select parent: "MBAGALA"
3. Switch back to Main Location
4. Parent dropdown disappears
5. Selected parent cleared

Expected:
✅ UI updates correctly
✅ No parent saved when main selected
```

### **Test 5: Reset After Add**
```
Actions:
1. Add sublocation "MBAGALA-A" with parent "MBAGALA"
2. Click [+]

Expected:
✅ Location added
✅ Text field cleared
✅ Type reset to "Main Location"
✅ Parent selection cleared
```

---

## 🎯 Benefits

### **User Experience:**
- ✅ **Clear hierarchy** - Define relationships during creation
- ✅ **Flexible** - Can create main or sublocations
- ✅ **Guided** - Radio buttons make it obvious
- ✅ **Validated** - Required fields enforced

### **Data Integrity:**
- ✅ **Structured** - Proper type and parent fields
- ✅ **Consistent** - All locations properly categorized
- ✅ **Analyzable** - Hierarchy visible in analytics
- ✅ **Backward compatible** - Legacy locations still work

### **Business Value:**
- ✅ **Better organization** - Locations properly grouped
- ✅ **Accurate analytics** - Main locations show totals
- ✅ **Easier management** - Clear parent-child relationships
- ✅ **Scalable** - Can add unlimited sublocations

---

## 🔗 Integration with Location Analytics

### **After Creating Locations:**

**Main Location Card:**
```
🏆 MBAGALA
🌳 3 sublocations
Revenue: 500.0M
```

**Tap for Details:**
```
MBAGALA
Includes 3 sublocations

Sublocation Breakdown:
├─ MBAGALA-A: 150.0M
├─ MBAGALA-B: 200.0M
└─ MBAGALA-C: 150.0M
```

---

## 📝 Code Changes Summary

### **1. LocationController (`location_controller.dart`):**
```dart
// Enhanced to accept type and parent location
Future<void> addLocation(
  String newLocation, {
  String? type,
  String? parentLocation,
}) async {
  final data = <String, dynamic>{};
  if (type != null) data['type'] = type;
  if (parentLocation != null) data['parent_location'] = parentLocation;
  await docRef.set(data);
}
```

### **2. GenerateUserScreen (`GenerateUserScreen.dart`):**
```dart
// Added state variables
String? selectedParentLocation;
bool isMainLocation = true;

// Added UI
- Radio buttons for type selection
- Conditional parent dropdown
- Validation for sublocation parent
- Auto-reset after adding

// Updated _addLocation()
await locationController.addLocation(
  newLoc,
  type: isMainLocation ? 'main' : 'sublocation',
  parentLocation: isMainLocation ? null : selectedParentLocation,
);
```

---

## ✅ Implementation Complete

### **Features Added:**
1. ✅ Location type selection (Main/Sublocation)
2. ✅ Parent location dropdown for sublocations
3. ✅ Validation for sublocation parent
4. ✅ Warning when no main locations exist
5. ✅ Auto-reset after adding location
6. ✅ Firestore data structure updated

### **User Flow:**
1. ✅ Enter location name
2. ✅ Choose type (radio buttons)
3. ✅ Select parent (if sublocation)
4. ✅ Click add
5. ✅ Location created with hierarchy
6. ✅ Appears in analytics properly

**Location hierarchy in user generation is ready!** 🎯
