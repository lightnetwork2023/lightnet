# Callback Integration for Home User Payments

## Overview
The `/callback` endpoint now automatically detects home user payments and stores them in Firestore via Cloud Function, while maintaining all existing functionality for other payment types.

## What I Changed

### Modified Endpoint: `/callback`
**File:** `app.py`

**New Logic Flow:**
```
1. Receive callback from AzamPay
2. Extract location from additionalProperties
3. Check if location == 'HOME_USER'
4. If YES → Call Cloud Function to store in Firestore
5. If NO → Continue with existing logic (unifi, vouchers, bulk users)
```

## How It Works

### Home User Payment Detection:
```python
if location == 'HOME_USER' and status == 'success':
    # Extract payment details
    customer_id = additional_properties.get('quantity')  # Customer ID
    amount = float(callback_data.get('amount', 0))
    phone = callback_data.get('msisdn', callback_data.get('accountNumber', ''))
    provider = callback_data.get('operator', 'Unknown')
    reference = callback_data.get('transactionId', callback_data.get('externalId', ''))
    
    # Call Cloud Function
    cloud_function_response = requests.post(
        'https://us-central1-lightnet-d2de9.cloudfunctions.net/storeHomeUserPayment',
        json={
            'customerId': customer_id,
            'amount': amount,
            'phone': phone,
            'provider': provider,
            'reference': reference,
            'createdByName': 'Home User Payment'
        },
        timeout=10
    )
```

## Payment Flow

### Complete End-to-End Flow:

```
1. Home User App
   ↓ (Makes payment)
   
2. Flask API (/make-paymentagent)
   ↓ (Initiates payment)
   
3. AzamPay API
   ↓ (Processes payment)
   
4. AzamPay Callback
   ↓ (Sends success notification)
   
5. Flask /callback endpoint
   ↓ (Detects location='HOME_USER')
   
6. Cloud Function (storeHomeUserPayment)
   ↓ (Stores in Firestore)
   
7. Firestore: home_customers/{id}/payments
   ↓
   
8. Boss Dashboard (sees payment immediately)
```

## Callback Payload Structure

### What AzamPay Sends:
```json
{
  "transactionstatus": "success",
  "amount": "50000",
  "msisdn": "0712345678",
  "operator": "Airtel",
  "transactionId": "AZM123456789",
  "externalId": "uuid-here",
  "additionalProperties": {
    "location": "HOME_USER",
    "quantity": "12345",
    "duration": "2592000",
    "days": "30"
  }
}
```

### Key Fields:
- **location**: `"HOME_USER"` - Identifies as home user payment
- **quantity**: `"12345"` - Customer ID (5-digit)
- **transactionstatus**: `"success"` - Payment succeeded
- **amount**: Payment amount in TZS
- **msisdn**: Customer's phone number
- **operator**: Payment provider (Airtel, Tigo, Mpesa, etc.)

## Data Mapping

### From Callback → Cloud Function:

| Callback Field | Cloud Function Field | Description |
|---------------|---------------------|-------------|
| `additionalProperties.quantity` | `customerId` | Customer's 5-digit ID |
| `amount` | `amount` | Payment amount |
| `msisdn` or `accountNumber` | `phone` | Customer's phone |
| `operator` | `provider` | Payment provider |
| `transactionId` or `externalId` | `reference` | Transaction reference |
| (hardcoded) | `createdByName` | "Home User Payment" |

## Existing Functionality Preserved

### 1. **Unifi Payments** (location = 'unifi')
- Forwards to external PHP endpoint
- No changes to existing logic

### 2. **Bulk User Generation** (quantity > 0 and location != 'HOME_USER')
- Generates multiple vouchers
- Stores in MySQL payments table
- No changes to existing logic

### 3. **Regular Voucher Payments** (has voucher field)
- Creates RADIUS voucher
- Stores in MySQL
- Authenticates via MikroTik
- No changes to existing logic

## Testing

### Test Home User Payment Callback:

**Using curl:**
```bash
curl -X POST http://167.179.100.104:5000/callback \
  -H "Content-Type: application/json" \
  -d '{
    "transactionstatus": "success",
    "amount": "1000",
    "msisdn": "0712345678",
    "operator": "Airtel",
    "transactionId": "TEST-123",
    "externalId": "test-uuid",
    "additionalProperties": {
      "location": "HOME_USER",
      "quantity": "12345",
      "duration": "2592000",
      "days": "30"
    }
  }'
```

**Expected Response:**
```json
{
  "success": true,
  "message": "Home user payment recorded successfully",
  "customerId": "12345"
}
```

### Test End-to-End:

1. **Make payment as home user** in app
2. **Check Flask logs** for callback received
3. **Verify Cloud Function called:**
   ```
   ✅ Home user payment stored in Firestore for customer 12345
   ```
4. **Check Firestore:**
   - Navigate to `home_customers/12345/payments`
   - Payment record should exist
5. **Check Boss Dashboard:**
   - Login as boss
   - View customer payments
   - Payment should appear

## Error Handling

### Scenario 1: Cloud Function Fails
```python
if cloud_function_response.status_code == 200:
    print(f"✅ Home user payment stored in Firestore for customer {customer_id}")
    return jsonify({'success': True, ...}), 200
else:
    print(f"⚠️ Failed to store home user payment: {cloud_function_response.text}")
    return jsonify({'success': False, 'error': '...'}), 500
```

### Scenario 2: Customer ID Missing
```python
customer_id = additional_properties.get('quantity')  # Will be None if missing
# Cloud Function will validate and return 400 error
```

### Scenario 3: Payment Status Not Success
```python
if location == 'HOME_USER' and status == 'success':
    # Only processes successful payments
# Failed payments are ignored
```

## Monitoring

### Check Flask Logs:

**Success:**
```
✅ Home user payment stored in Firestore for customer 12345
```

**Failure:**
```
⚠️ Failed to store home user payment: {"error": "Customer not found"}
```

**Error:**
```
❌ Error storing home user payment: Connection timeout
```

### Check Cloud Function Logs:

```bash
firebase functions:log --only storeHomeUserPayment
```

Look for:
- Payment storage success
- Customer validation errors
- Firestore write errors

## Advantages

### ✅ Automatic Processing
- No manual intervention needed
- Payment recorded immediately after success
- Boss sees payment in real-time

### ✅ Separation of Concerns
- Home user payments → Firestore (via Cloud Function)
- Regular payments → MySQL (existing logic)
- Clean separation by location field

### ✅ Backward Compatible
- All existing payment flows unchanged
- Only adds new logic for HOME_USER location
- No breaking changes

### ✅ Centralized Logic
- Single callback endpoint handles all payment types
- Easy to maintain and debug
- Consistent error handling

## Security Considerations

### ✅ What's Secure:
- Validates payment status is 'success'
- Cloud Function validates customer exists
- Uses HTTPS for Cloud Function calls
- Logs all operations

### ⚠️ Considerations:
- Callback endpoint has no authentication (relies on AzamPay)
- Anyone can POST to /callback (but needs valid data)
- Consider adding AzamPay signature verification

### Future Enhancement - Verify AzamPay Signature:
```python
def verify_azampay_signature(payload, signature):
    # Verify the callback is actually from AzamPay
    expected_signature = hmac.new(
        AZAM_WEBHOOK_SECRET.encode(),
        json.dumps(payload).encode(),
        hashlib.sha256
    ).hexdigest()
    return hmac.compare_digest(expected_signature, signature)

# In callback:
signature = request.headers.get('X-AzamPay-Signature')
if not verify_azampay_signature(callback_data, signature):
    return jsonify({'error': 'Invalid signature'}), 401
```

## Troubleshooting

### Payment succeeds but not in Firestore

**Check:**
1. Flask logs for callback received
2. Cloud Function URL correct?
3. Cloud Function deployed?
4. Customer ID exists?

**Solution:**
```bash
# Check Flask logs
tail -f /path/to/flask.log

# Verify Cloud Function
firebase functions:list

# Test Cloud Function directly
curl -X POST https://us-central1-lightnet-d2de9.cloudfunctions.net/storeHomeUserPayment \
  -H "Content-Type: application/json" \
  -d '{"customerId":"12345","amount":1000,"phone":"0712345678","provider":"Airtel"}'
```

### Error: "Failed to record payment in Firestore"

**Cause:** Cloud Function returned non-200 status

**Solution:**
- Check Cloud Function logs
- Verify customer exists
- Check Firestore permissions

### Callback not received

**Cause:** AzamPay not configured to send callbacks

**Solution:**
- Configure webhook URL in AzamPay dashboard
- URL should be: `http://167.179.100.104:5000/callback`
- Ensure Flask server is accessible from internet

## Configuration

### AzamPay Webhook Setup:

1. **Login to AzamPay Dashboard**
2. **Go to Settings → Webhooks**
3. **Add Webhook URL:**
   ```
   http://167.179.100.104:5000/callback
   ```
4. **Select Events:**
   - Payment Success
   - Payment Failed (optional)
5. **Save Configuration**

### Test Webhook:

AzamPay dashboard usually has a "Test Webhook" button to send a test callback.

## Summary

The callback endpoint now:
- ✅ Detects home user payments by `location = 'HOME_USER'`
- ✅ Automatically calls Cloud Function to store in Firestore
- ✅ Maintains all existing functionality for other payment types
- ✅ Provides proper error handling and logging
- ✅ Enables real-time payment visibility for boss
- ✅ No manual intervention needed

**Result:** Home user payments are automatically recorded in Firestore when AzamPay sends the success callback, making them immediately visible in the boss dashboard.
