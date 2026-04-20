<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\FirestoreService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
class ApiCartController extends Controller
{
    private const MAX_QUANTITY = 5;

    public function __construct(private FirestoreService $firestore)
    {
    }

    /**
     * List cart items for the authenticated customer (Firestore `cart_items`).
     * GET /api/v1/cart
     */
    public function index(Request $request): JsonResponse
    {
        $customerId = (string) $request->user()->id;
        $items = collect($this->firestore->where('cart_items', 'customer_id', $customerId))
            ->sortByDesc(fn (array $row) => (string) ($row['created_at'] ?? ''))
            ->values()
            ->map(fn (array $row) => $this->cartItemToArray($row));

        $subtotal = $items->sum('line_total');

        return response()->json([
            'success' => true,
            'data' => [
                'items' => $items,
                'subtotal' => round((float) $subtotal, 2),
                'count' => $items->count(),
            ],
        ]);
    }

    /**
     * Add to cart (or update quantity if same flavor + gallon already in cart).
     * POST /api/v1/cart
     * Body: { "flavor_id": "<firestore doc id>", "gallon_id": "<firestore doc id>", "quantity": 1 }
     * Or: { "flavor_id": "...", "gallon_size": "2 gal", "quantity": 1 } when the client has no gallon doc id.
     * Optional: "flavor_name" — resolved if flavor_id is wrong/missing (e.g. clients that only keep numeric ids).
     */
    public function store(Request $request): JsonResponse
    {
        $request->validate([
            'flavor_id' => 'nullable|string',
            'flavor_name' => 'nullable|string|max:255',
            'gallon_id' => 'nullable|string',
            'gallon_size' => 'nullable|string|max:100',
            'quantity' => 'required|integer|min:1|max:'.self::MAX_QUANTITY,
        ]);

        $customerId = (string) $request->user()->id;
        $flavorIdRaw = trim((string) $request->input('flavor_id', ''));
        $gallonIdRaw = trim((string) $request->input('gallon_id', ''));
        $gallonSizeRaw = trim((string) $request->input('gallon_size', ''));
        $flavorNameFallback = $request->input('flavor_name');
        $quantity = (int) $request->quantity;

        if ($flavorIdRaw === '' && (! is_string($flavorNameFallback) || trim($flavorNameFallback) === '')) {
            return response()->json([
                'success' => false,
                'message' => 'flavor_id or flavor_name is required.',
            ], 422);
        }

        if ($gallonIdRaw === '' && $gallonSizeRaw === '') {
            return response()->json([
                'success' => false,
                'message' => 'gallon_id or gallon_size is required.',
            ], 422);
        }

        $flavor = $this->resolveFlavor($flavorIdRaw, is_string($flavorNameFallback) ? $flavorNameFallback : null);
        $gallon = $this->resolveGallon($gallonIdRaw !== '' ? $gallonIdRaw : null, $gallonSizeRaw !== '' ? $gallonSizeRaw : null);

        if (! $flavor || ! $gallon) {
            return response()->json([
                'success' => false,
                'message' => 'Invalid flavor or gallon.',
            ], 422);
        }

        $flavorId = (string) ($flavor['id'] ?? $flavorIdRaw);
        $gallonId = (string) ($gallon['id'] ?? $gallonIdRaw);

        $existing = $this->findCartRow($customerId, $flavorId, $gallonId);

        if ($existing) {
            $newQty = min(self::MAX_QUANTITY, (int) ($existing['quantity'] ?? 0) + $quantity);
            $this->firestore->update('cart_items', (string) $existing['id'], ['quantity' => $newQty]);
            $row = $this->firestore->get('cart_items', (string) $existing['id']) ?? array_merge($existing, ['quantity' => $newQty]);
            $message = 'Cart updated.';
        } else {
            $newId = $this->firestore->add('cart_items', [
                'customer_id' => $customerId,
                'flavor_id' => $flavorId,
                'gallon_id' => $gallonId,
                'quantity' => $quantity,
                'created_at' => now()->toIso8601String(),
            ]);
            $row = $this->firestore->get('cart_items', $newId);
            $message = 'Added to cart.';
        }

        if (! $row) {
            return response()->json(['success' => false, 'message' => 'Could not save cart.'], 500);
        }

        return response()->json([
            'success' => true,
            'message' => $message,
            'data' => $this->cartItemToArray($row),
        ], 201);
    }

    /**
     * Update cart item quantity.
     * PUT/PATCH /api/v1/cart/{id}
     */
    public function update(Request $request, string $id): JsonResponse
    {
        $request->validate([
            'quantity' => 'required|integer|min:1|max:'.self::MAX_QUANTITY,
        ]);

        $customerId = (string) $request->user()->id;
        $item = $this->firestore->get('cart_items', $id);
        if (! $item || (string) ($item['customer_id'] ?? '') !== $customerId) {
            return response()->json(['success' => false, 'message' => 'Cart item not found.'], 404);
        }

        $this->firestore->update('cart_items', $id, ['quantity' => (int) $request->quantity]);
        $item = $this->firestore->get('cart_items', $id) ?? array_merge($item, ['quantity' => (int) $request->quantity]);

        return response()->json([
            'success' => true,
            'message' => 'Cart updated.',
            'data' => $this->cartItemToArray($item),
        ]);
    }

    /**
     * Remove item from cart.
     * DELETE /api/v1/cart/{id}
     */
    public function destroy(Request $request, string $id): JsonResponse
    {
        $customerId = (string) $request->user()->id;
        $item = $this->firestore->get('cart_items', $id);
        if (! $item || (string) ($item['customer_id'] ?? '') !== $customerId) {
            return response()->json(['success' => false, 'message' => 'Cart item not found.'], 404);
        }
        $this->firestore->delete('cart_items', $id);

        return response()->json([
            'success' => true,
            'message' => 'Removed from cart.',
        ]);
    }

    private function findCartRow(string $customerId, string $flavorId, string $gallonId): ?array
    {
        $rows = $this->firestore->where('cart_items', 'customer_id', $customerId);

        foreach ($rows as $row) {
            if ((string) ($row['flavor_id'] ?? '') === $flavorId && (string) ($row['gallon_id'] ?? '') === $gallonId) {
                return $row;
            }
        }

        return null;
    }

    /**
     * Resolve flavor by Firestore document id, or by exact name if id lookup fails.
     */
    private function resolveFlavor(string $documentId, ?string $nameFallback): ?array
    {
        if ($documentId !== '') {
            $f = $this->firestore->get('flavors', $documentId);
            if ($f) {
                return $f;
            }
        }
        $name = trim((string) ($nameFallback ?? ''));
        if ($name === '') {
            return null;
        }

        return $this->firestore->firstWhere('flavors', 'name', $name);
    }

    /**
     * Resolve gallon by document id, or by size label (case-insensitive, normalized spaces).
     */
    private function resolveGallon(?string $documentId, ?string $sizeLabel): ?array
    {
        if ($documentId !== null && $documentId !== '') {
            $g = $this->firestore->get('gallons', $documentId);
            if ($g) {
                return $g;
            }
        }
        if ($sizeLabel === null || trim($sizeLabel) === '') {
            return null;
        }
        $want = $this->normalizeSizeLabel($sizeLabel);
        foreach ($this->firestore->all('gallons') as $row) {
            $s = $this->normalizeSizeLabel((string) ($row['size'] ?? $row['name'] ?? ''));
            if ($s !== '' && $s === $want) {
                return $row;
            }
        }

        return null;
    }

    private function normalizeSizeLabel(string $label): string
    {
        $s = strtolower(preg_replace('/\s+/u', ' ', trim($label)));

        return $s;
    }

    private function cartItemToArray(array $item): array
    {
        $flavor = $this->firestore->get('flavors', (string) ($item['flavor_id'] ?? ''));
        $gallon = $this->firestore->get('gallons', (string) ($item['gallon_id'] ?? ''));

        $flavorPrice = $flavor ? (float) ($flavor['price'] ?? 0) : 0;
        $addonPrice = $gallon ? (float) ($gallon['addon_price'] ?? 0) : 0;
        $qty = (int) ($item['quantity'] ?? 0);
        $lineTotal = ($flavorPrice + $addonPrice) * $qty;

        return [
            'id' => isset($item['id']) ? (string) $item['id'] : null,
            'flavor_id' => isset($item['flavor_id']) ? (string) $item['flavor_id'] : null,
            'gallon_id' => isset($item['gallon_id']) ? (string) $item['gallon_id'] : null,
            'quantity' => $qty,
            'flavor' => $flavor ? [
                'id' => isset($flavor['id']) ? (string) $flavor['id'] : null,
                'name' => $flavor['name'] ?? null,
                'category' => $flavor['category'] ?? null,
                'price' => $flavorPrice,
                'image' => $flavor['image'] ?? null,
                'mobile_image' => $flavor['mobile_image'] ?? null,
            ] : null,
            'gallon' => $gallon ? [
                'id' => isset($gallon['id']) ? (string) $gallon['id'] : null,
                'size' => $gallon['size'] ?? null,
                'addon_price' => $addonPrice,
                'image' => $gallon['image'] ?? null,
            ] : null,
            'line_total' => round($lineTotal, 2),
            'created_at' => $item['created_at'] ?? null,
        ];
    }
}
