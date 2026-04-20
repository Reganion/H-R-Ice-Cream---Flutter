# Why "Address Details" updates don't notify admin

## Cause

The Flutter app has **two** ways to handle address:

| Flow | API | Laravel controller | Admin notification? |
|------|-----|--------------------|----------------------|
| Single address on customer | PUT/POST `/api/v1/address` | `ApiAuthController::updateAddress` | ✅ Yes |
| **Multiple addresses (Address Details page)** | POST `/api/v1/addresses`, PUT `/api/v1/addresses/{id}` | **ApiAddressController** (store, update) | ❌ No |

When the user taps **Profile → Address Details** and edits or adds an address, the app calls:
- `Auth().updateAddressById(id, ...)` → **PUT /api/v1/addresses/{id}**
- `Auth().addAddress(...)` → **POST /api/v1/addresses**

Those are handled by **ApiAddressController**, not by `ApiAuthController::updateAddress`. So the admin notification (which is only in `updateAddress`) is never run.

## Fix

In your **ApiAddressController** (in your main Laravel project), after a successful **store** (add address) or **update** (edit address), notify all admins using the logged-in customer.

1. At the top of the controller add:
   ```php
   use App\Models\AdminNotification;
   use App\Models\Customer;
   ```

2. In the method that handles **POST /addresses** (e.g. `store`), after you save the new address and return success, add:
   ```php
   $customer = $request->user();
   if ($customer instanceof Customer) {
       AdminNotification::notifyAddressUpdated($customer);
   }
   ```

3. In the method that handles **PUT /addresses/{id}** (e.g. `update`), after you save the address and return success, add the same:
   ```php
   $customer = $request->user();
   if ($customer instanceof Customer) {
       AdminNotification::notifyAddressUpdated($customer);
   }
   ```

So both "Add a new address" and "Edit" from the Address Details page will create an admin notification.

## Example (pseudo-code)

```php
// In ApiAddressController

public function store(Request $request): JsonResponse
{
    // ... validation, create address (e.g. CustomerAddress::create([...])) ...
    
    $customer = $request->user();
    if ($customer instanceof Customer) {
        AdminNotification::notifyAddressUpdated($customer);
    }
    
    return response()->json([...], 201);
}

public function update(Request $request, int $id): JsonResponse
{
    // ... find address, validation, update ...
    
    $customer = $request->user();
    if ($customer instanceof Customer) {
        AdminNotification::notifyAddressUpdated($customer);
    }
    
    return response()->json([...]);
}
```

Your `AdminNotification` model already has `notifyAddressUpdated(Customer $customer)` and `createForAllAdmins`, so no change is needed there. Just add the two calls above in the addresses controller.
