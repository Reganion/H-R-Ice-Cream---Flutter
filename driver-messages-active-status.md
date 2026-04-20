# Driver messages: fetch only active status

When the app calls **GET /api/v1/driver/shipments/{id}/messages** with `status=active` (or by default), the backend should return only order messages where **order_messages.status** is active, so the driver and customer see only the active thread.

## 1. OrderMessage model

Ensure your `App\Models\OrderMessage` defines:

```php
const STATUS_ACTIVE = 'active';
const STATUS_ARCHIVE = 'archive';
```

(And that the `order_messages` table has a `status` column used for driver-side active/archive.)

## 2. driverMessages() – filter by active

In your `ApiOrderMessageController::driverMessages()` method, build the query so that **by default** only active messages are returned. Optional: if the client sends `include_archived=1`, return all messages.

Replace the line that builds the messages query with something like:

```php
$includeArchived = (bool) $request->query('include_archived', false);
$query = OrderMessage::query()
    ->where('order_id', $order->id)
    ->where('customer_id', $order->customer_id);

if (!$includeArchived) {
    $query->where('status', OrderMessage::STATUS_ACTIVE);
}

$messages = $query->orderBy('created_at')->paginate($perPage);
```

So:

- **No query param** or **status=active**: only messages with `status = 'active'` (what the app uses when you tap the message icon).
- **include_archived=1**: all messages (active + archived) for that order/customer.
