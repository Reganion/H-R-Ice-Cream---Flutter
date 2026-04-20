<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Models\AdminNotification;
use App\Services\FirebaseRealtimeService;
use App\Services\FirestoreService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Collection;

class ApiAddressController extends Controller
{
    public function __construct(
        protected FirestoreService $firestore,
        protected FirebaseRealtimeService $firebase,
    ) {}

    /**
     * List all addresses for the authenticated customer.
     * GET /api/v1/addresses
     */
    public function index(Request $request): JsonResponse
    {
        $customer = $request->user();
        if (! $this->isAuthenticatedCustomer($customer)) {
            return response()->json(['success' => false, 'message' => 'Not authenticated.'], 401);
        }

        $customerId = (string) $customer->id;
        $addresses = $this->addressesForCustomerOrdered($customerId)
            ->map(fn (array $a) => $this->addressToArray($a));

        return response()->json([
            'success' => true,
            'data' => [
                'addresses' => $addresses,
                'count' => $addresses->count(),
            ],
        ]);
    }

    /**
     * Add a new address.
     * POST /api/v1/addresses
     */
    public function store(Request $request): JsonResponse
    {
        $customer = $request->user();
        if (! $this->isAuthenticatedCustomer($customer)) {
            return response()->json(['success' => false, 'message' => 'Not authenticated.'], 401);
        }

        $customerId = (string) $customer->id;

        $request->validate([
            'firstname' => 'nullable|string|max:50',
            'lastname' => 'nullable|string|max:50',
            'contact_no' => 'nullable|string|max:20|regex:/^[\d\s\-+()]+$/',
            'province' => 'nullable|string|max:100',
            'city' => 'nullable|string|max:100',
            'barangay' => 'nullable|string|max:100',
            'postal_code' => 'nullable|string|max:20',
            'street_name' => 'nullable|string|max:255',
            'label_as' => 'nullable|string|max:50',
            'reason' => 'nullable|string|max:500',
            'is_default' => 'nullable|boolean',
        ]);

        $existing = $this->addressesForCustomer($customerId);
        $isDefault = $request->boolean('is_default');
        if ($isDefault) {
            $this->clearDefaultForCustomer($customerId);
        } elseif ($existing->isEmpty()) {
            $isDefault = true;
        }

        $newId = $this->firestore->add('customer_addresses', [
            'customer_id' => $customerId,
            'firstname' => $request->filled('firstname') ? trim((string) $request->firstname) : null,
            'lastname' => $request->filled('lastname') ? trim((string) $request->lastname) : null,
            'contact_no' => $request->filled('contact_no') ? trim((string) $request->contact_no) : null,
            'province' => $request->filled('province') ? trim((string) $request->province) : null,
            'city' => $request->filled('city') ? trim((string) $request->city) : null,
            'barangay' => $request->filled('barangay') ? trim((string) $request->barangay) : null,
            'postal_code' => $request->filled('postal_code') ? trim((string) $request->postal_code) : null,
            'street_name' => $request->filled('street_name') ? trim((string) $request->street_name) : null,
            'label_as' => $request->filled('label_as') ? trim((string) $request->label_as) : null,
            'reason' => $request->filled('reason') ? trim((string) $request->reason) : null,
            'is_default' => $isDefault,
        ]);

        $address = $this->firestore->get('customer_addresses', $newId);
        if (! $address) {
            return response()->json(['success' => false, 'message' => 'Could not save address.'], 500);
        }

        $freshCustomer = $this->firestore->get('customers', $customerId) ?? [];
        $this->notifyAdminsAddressUpdated($freshCustomer);

        return response()->json([
            'success' => true,
            'message' => 'Address added successfully.',
            'data' => $this->addressToArray($address),
        ], 201);
    }

    /**
     * Get a single address (must belong to the customer).
     * GET /api/v1/addresses/{id}
     */
    public function show(Request $request, string $id): JsonResponse
    {
        $customer = $request->user();
        if (! $this->isAuthenticatedCustomer($customer)) {
            return response()->json(['success' => false, 'message' => 'Not authenticated.'], 401);
        }

        $address = $this->getAddressForCustomer((string) $customer->id, $id);
        if (! $address) {
            return response()->json([
                'success' => false,
                'message' => 'Address not found.',
            ], 404);
        }

        return response()->json([
            'success' => true,
            'data' => $this->addressToArray($address),
        ]);
    }

    /**
     * Update an address.
     * PUT/PATCH /api/v1/addresses/{id}
     */
    public function update(Request $request, string $id): JsonResponse
    {
        $customer = $request->user();
        if (! $this->isAuthenticatedCustomer($customer)) {
            return response()->json(['success' => false, 'message' => 'Not authenticated.'], 401);
        }

        $customerId = (string) $customer->id;
        $address = $this->getAddressForCustomer($customerId, $id);
        if (! $address) {
            return response()->json([
                'success' => false,
                'message' => 'Address not found.',
            ], 404);
        }

        $request->validate([
            'firstname' => 'nullable|string|max:50',
            'lastname' => 'nullable|string|max:50',
            'contact_no' => 'nullable|string|max:20|regex:/^[\d\s\-+()]+$/',
            'province' => 'nullable|string|max:100',
            'city' => 'nullable|string|max:100',
            'barangay' => 'nullable|string|max:100',
            'postal_code' => 'nullable|string|max:20',
            'street_name' => 'nullable|string|max:255',
            'label_as' => 'nullable|string|max:50',
            'reason' => 'nullable|string|max:500',
            'is_default' => 'nullable|boolean',
        ]);

        $data = array_filter([
            'firstname' => $request->filled('firstname') ? trim((string) $request->firstname) : null,
            'lastname' => $request->filled('lastname') ? trim((string) $request->lastname) : null,
            'contact_no' => $request->filled('contact_no') ? trim((string) $request->contact_no) : null,
            'province' => $request->filled('province') ? trim((string) $request->province) : null,
            'city' => $request->filled('city') ? trim((string) $request->city) : null,
            'barangay' => $request->filled('barangay') ? trim((string) $request->barangay) : null,
            'postal_code' => $request->filled('postal_code') ? trim((string) $request->postal_code) : null,
            'street_name' => $request->filled('street_name') ? trim((string) $request->street_name) : null,
            'label_as' => $request->filled('label_as') ? trim((string) $request->label_as) : null,
            'reason' => $request->filled('reason') ? trim((string) $request->reason) : null,
        ], fn ($v) => $v !== null);

        if ($request->has('is_default') && $request->boolean('is_default')) {
            $this->clearDefaultForCustomerExcept($customerId, $id);
            $data['is_default'] = true;
        }

        if ($data !== []) {
            $this->firestore->update('customer_addresses', $id, $data);
        }

        $updated = $this->firestore->get('customer_addresses', $id) ?? array_merge($address, $data);

        $freshCustomer = $this->firestore->get('customers', $customerId) ?? [];
        $this->notifyAdminsAddressUpdated($freshCustomer);

        return response()->json([
            'success' => true,
            'message' => 'Address updated successfully.',
            'data' => $this->addressToArray($updated),
        ]);
    }

    /**
     * Delete an address.
     * DELETE /api/v1/addresses/{id}
     */
    public function destroy(Request $request, string $id): JsonResponse
    {
        $customer = $request->user();
        if (! $this->isAuthenticatedCustomer($customer)) {
            return response()->json(['success' => false, 'message' => 'Not authenticated.'], 401);
        }

        $customerId = (string) $customer->id;
        $address = $this->getAddressForCustomer($customerId, $id);
        if (! $address) {
            return response()->json([
                'success' => false,
                'message' => 'Address not found.',
            ], 404);
        }

        $wasDefault = (bool) ($address['is_default'] ?? false);
        $this->firestore->delete('customer_addresses', $id);

        if ($wasDefault) {
            $first = $this->addressesForCustomer($customerId)
                ->sortBy(fn (array $a) => (string) ($a['created_at'] ?? ''))
                ->first();
            if ($first && ! empty($first['id'])) {
                $this->firestore->update('customer_addresses', (string) $first['id'], ['is_default' => true]);
            }
        }

        return response()->json([
            'success' => true,
            'message' => 'Address deleted.',
        ]);
    }

    /**
     * Set an address as the default.
     * POST /api/v1/addresses/{id}/default
     */
    public function setDefault(Request $request, string $id): JsonResponse
    {
        $customer = $request->user();
        if (! $this->isAuthenticatedCustomer($customer)) {
            return response()->json(['success' => false, 'message' => 'Not authenticated.'], 401);
        }

        $customerId = (string) $customer->id;
        $address = $this->getAddressForCustomer($customerId, $id);
        if (! $address) {
            return response()->json([
                'success' => false,
                'message' => 'Address not found.',
            ], 404);
        }

        $this->clearDefaultForCustomer($customerId);
        $this->firestore->update('customer_addresses', $id, ['is_default' => true]);

        $updated = $this->firestore->get('customer_addresses', $id) ?? array_merge($address, ['is_default' => true]);

        $freshCustomer = $this->firestore->get('customers', $customerId) ?? [];
        $this->notifyAdminsAddressUpdated($freshCustomer);

        return response()->json([
            'success' => true,
            'message' => 'Default address updated.',
            'data' => $this->addressToArray($updated),
        ]);
    }

    private function addressesForCustomer(string $customerId): Collection
    {
        return collect($this->firestore->where('customer_addresses', 'customer_id', $customerId))
            ->values();
    }

    /**
     * Default first, then oldest created.
     */
    private function addressesForCustomerOrdered(string $customerId): Collection
    {
        return $this->addressesForCustomer($customerId)
            ->sort(function (array $a, array $b) {
                $ad = (bool) ($a['is_default'] ?? false);
                $bd = (bool) ($b['is_default'] ?? false);
                if ($ad !== $bd) {
                    return $ad ? -1 : 1;
                }

                return strcmp((string) ($a['created_at'] ?? ''), (string) ($b['created_at'] ?? ''));
            })
            ->values();
    }

    private function getAddressForCustomer(string $customerId, string $addressId): ?array
    {
        $row = $this->firestore->get('customer_addresses', $addressId);
        if (! $row || (string) ($row['customer_id'] ?? '') !== $customerId) {
            return null;
        }

        return $row;
    }

    private function clearDefaultForCustomer(string $customerId): void
    {
        foreach ($this->addressesForCustomer($customerId) as $addr) {
            if (! empty($addr['id']) && ($addr['is_default'] ?? false)) {
                $this->firestore->update('customer_addresses', (string) $addr['id'], ['is_default' => false]);
            }
        }
    }

    private function clearDefaultForCustomerExcept(string $customerId, string $exceptId): void
    {
        foreach ($this->addressesForCustomer($customerId) as $addr) {
            $aid = (string) ($addr['id'] ?? '');
            if ($aid === '' || $aid === $exceptId) {
                continue;
            }
            if ($addr['is_default'] ?? false) {
                $this->firestore->update('customer_addresses', $aid, ['is_default' => false]);
            }
        }
    }

    private function notifyAdminsAddressUpdated(array $customer): void
    {
        if ($customer === []) {
            return;
        }
        $name = trim((string) (($customer['firstname'] ?? '').' '.($customer['lastname'] ?? '')));
        if ($name === '') {
            $name = (string) ($customer['email'] ?? 'Customer');
        }
        $admins = $this->firestore->all('admins');
        foreach ($admins as $admin) {
            if (empty($admin['id'])) {
                continue;
            }
            $this->firestore->add('admin_notifications', [
                'user_id' => (string) $admin['id'],
                'type' => AdminNotification::TYPE_ADDRESS_UPDATE,
                'title' => $name,
                'message' => null,
                'image_url' => $customer['image'] ?? null,
                'related_type' => 'Customer',
                'related_id' => (string) ($customer['id'] ?? ''),
                'data' => ['subtitle' => 'updated their', 'highlight' => 'Address'],
                'read_at' => null,
            ]);
        }
        try {
            $this->firebase->touchAdminNotificationsUpdated();
        } catch (\Throwable $e) {
            report($e);
        }
    }

    private function addressToArray(array $address): array
    {
        $full = $this->buildFullAddress($address);

        return [
            'id' => $address['id'] ?? null,
            'customer_id' => $address['customer_id'] ?? null,
            'firstname' => $address['firstname'] ?? null,
            'lastname' => $address['lastname'] ?? null,
            'contact_no' => $address['contact_no'] ?? null,
            'province' => $address['province'] ?? null,
            'city' => $address['city'] ?? null,
            'barangay' => $address['barangay'] ?? null,
            'postal_code' => $address['postal_code'] ?? null,
            'street_name' => $address['street_name'] ?? null,
            'label_as' => $address['label_as'] ?? null,
            'reason' => $address['reason'] ?? null,
            'is_default' => (bool) ($address['is_default'] ?? false),
            'full_address' => $full,
            'created_at' => $address['created_at'] ?? null,
            'updated_at' => $address['updated_at'] ?? null,
        ];
    }

    private function buildFullAddress(array $address): string
    {
        $city = $address['city'] ?? null;
        $parts = array_filter([
            $address['street_name'] ?? null,
            $address['barangay'] ?? null,
            $city ? $city.' City' : null,
            $address['province'] ?? null,
            $address['postal_code'] ?? null,
        ]);

        return implode(', ', $parts) ?: '';
    }

    private function isAuthenticatedCustomer(mixed $customer): bool
    {
        return is_object($customer) && isset($customer->id) && (string) $customer->id !== '';
    }
}
