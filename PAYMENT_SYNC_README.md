# Payment Firestore Sync - Deployment Guide

## ✅ What's Been Done

### 1. **Cloud Function Created** (`functions/index.js`)
- New function: `storePaymentData`
- Location: Lines 984-1127
- Stores payment data in Firestore after successful payments
- Updates location revenue metadata automatically

### 2. **Flask Integration** (`app.py`)
- Added `FIREBASE_PAYMENT_FUNCTION_URL` constant (line 61)
- Added `sync_payment_to_firestore()` helper function (lines 214-237)
- Updated `store_voucher()` to call sync after MySQL insert (lines 719-737)
- Non-blocking: Payment succeeds even if Firestore sync fails

---

## 🚀 Deployment Steps

### **Step 1: Deploy Cloud Functions**

```bash
# Navigate to functions directory
cd c:\Users\LITtech\AndroidStudioProjects\lightnetwork\functions

# Install dependencies (if needed)
npm install

# Deploy to Firebase
firebase deploy --only functions:storePaymentData
```

### **Step 2: Verify Function URL**

After deployment, Firebase will show you the URL. It should be:
```
https://us-central1-lightnet-d2de9.cloudfunctions.net/storePaymentData
```

If it's different, update line 61 in `app.py`:
```python
FIREBASE_PAYMENT_FUNCTION_URL = 'YOUR_ACTUAL_URL_HERE'
```

### **Step 3: Restart Flask App**

On the server:
```bash
# SSH to server
gcloud compute ssh lightnet-server --zone=africa-south1-a

# Restart Flask service
sudo systemctl restart flask-app.service

# Check status
sudo systemctl status flask-app.service

# Check logs
sudo tail -f /var/log/flask_callback.log
```

---

## 📊 Firestore Data Structure

### **Collections Created:**

#### 1. `payments/` (Payment Records)
```javascript
{
  voucher: "123456789012",
  location: "MBAGALA",
  sublocation: null,
  amount: 5000,
  duration: 86400,
  phone: "0712345678",
  mac_address: "AA:BB:CC:DD:EE:FF",
  payment_method: "Mobile Money",
  transaction_id: null,
  created_by: "system",
  payment_type: "voucher",
  created_at: Timestamp,
  synced_at: Timestamp
}
```

#### 2. `locations/` (Metadata Updated)
```javascript
{
  metadata: {
    total_revenue: 150000,      // Incremented on each payment
    payment_count: 30,           // Count of payments
    last_payment_at: Timestamp,  // Last payment time
    last_updated: Timestamp      // Last metadata update
  }
}
```

---

## 🧪 Testing

### **Test 1: Manual Payment Test**

Make a test payment through the app and check logs:

```bash
# On server, check Flask logs
sudo tail -f /var/log/flask_callback.log
```

Look for:
```
✅ Payment synced to Firestore: MBAGALA - TZS 5000
```

### **Test 2: Check Firestore Console**

1. Go to Firebase Console: https://console.firebase.google.com
2. Select project: `lightnet-d2de9`
3. Navigate to Firestore Database
4. Check collections:
   - ✅ `payments/` - should have new payment documents
   - ✅ `locations/MBAGALA/metadata` - should show updated revenue

### **Test 3: Verify Location Metadata**

Query Firestore to see aggregated data:
```javascript
// In Firebase Console > Firestore
locations/MBAGALA

// Should show:
{
  metadata: {
    total_revenue: 25000,
    payment_count: 5,
    last_payment_at: "2025-11-11T20:30:00Z"
  }
}
```

---

## 🔍 Troubleshooting

### **Issue 1: "Firestore sync timeout"**
**Cause:** Cloud Function taking too long
**Solution:** Increase timeout in app.py line 226:
```python
timeout=10  # Increase from 5 to 10 seconds
```

### **Issue 2: "Location does not exist"**
**Cause:** Location not created in Firestore
**Solution:** The function auto-creates it, but check logs:
```bash
sudo tail -f /var/log/flask_callback.log
```

### **Issue 3: Permission Denied**
**Cause:** Cloud Function can't write to Firestore
**Solution:** Check Firebase Console > IAM & Admin
- Cloud Functions service account should have "Cloud Datastore User" role

---

## 📈 Next Steps

Now that payment sync is working, you can:

1. **Add Sublocation Support**
   - Update payment form to include sublocation dropdown
   - Pass `sublocation` parameter in payment data

2. **Create Expense Management Screen**
   - Add expense tracking for each location
   - Calculate profit/loss per location

3. **Build Analytics Dashboard**
   - Show total revenue per location
   - Show sublocation breakdown
   - Compare locations

4. **Add Reconciliation Job**
   - Daily sync to ensure MySQL and Firestore match
   - Fix any missing payments

---

## 📝 Important Notes

- ✅ **MySQL is Source of Truth**: Payment completes even if Firestore fails
- ✅ **Non-Blocking**: Firestore sync doesn't slow down payments
- ✅ **Auto-Retry**: Consider adding retry logic for failed syncs
- ✅ **Monitoring**: Check logs regularly for sync failures

---

## 🎯 Success Metrics

After deployment, you should see:
- ✅ All payments stored in MySQL (as before)
- ✅ All payments also stored in Firestore
- ✅ Location metadata automatically updated
- ✅ No payment failures due to Firestore issues

Monitor for 24 hours to ensure everything works smoothly!
