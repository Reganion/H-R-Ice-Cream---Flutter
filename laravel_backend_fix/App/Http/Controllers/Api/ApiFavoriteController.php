<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\FirestoreService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ApiFavoriteController extends Controller
{
    public function __construct(private FirestoreService $firestore)
    {
    }

    /**
     * List favorites for the authenticated customer (Firestore `favorites`).
     * GET /api/v1/favorites
     */
    public function index(Request $request): JsonResponse
    {
        $customerId = (string) $request->user()->id;
        $rows = collect($this->firestore->where('favorites', 'customer_id', $customerId))
            ->sortByDesc(fn (array $r) => (string) ($r['created_at'] ?? ''))
            ->values();

        $favorites = $rows->map(function (array $row) {
            $f = $this->firestore->get('flavors', (string) ($row['flavor_id'] ?? ''));

            return $f ? $this->ensureStringFlavorId($f) : null;
        })->filter()->values()->all();

        return response()->json([
            'success' => true,
            'data' => $favorites,
        ]);
    }

    /**
     * Add a flavor to favorites (toggle: if already in favorites, remove it).
     * POST /api/v1/favorites
     * Body: { "flavor_id": "<Firestore flavor document id>" }
     * Or: { "flavor_name": "Vanilla" } if the client lost the string document id (e.g. parsed id as int).
     */
    public function store(Request $request): JsonResponse
    {
        $request->validate([
            'flavor_id' => 'nullable|string',
            'flavor_name' => 'nullable|string|max:255',
        ]);

        $customerId = (string) $request->user()->id;
        $flavorIdRaw = trim((string) $request->input('flavor_id', ''));
        $nameFallback = $request->input('flavor_name');

        if ($flavorIdRaw === '' && (! is_string($nameFallback) || trim($nameFallback) === '')) {
            return response()->json([
                'success' => false,
                'message' => 'flavor_id or flavor_name is required.',
            ], 422);
        }

        $flavor = $this->resolveFlavor($flavorIdRaw, is_string($nameFallback) ? $nameFallback : null);
        if (! $flavor) {
            return response()->json(['success' => false, 'message' => 'Flavor not found.'], 404);
        }

        $flavorId = (string) ($flavor['id'] ?? '');

        $existing = $this->findFavoriteRow($customerId, $flavorId);
        if ($existing) {
            $this->firestore->delete('favorites', (string) $existing['id']);

            return response()->json([
                'success' => true,
                'message' => 'Removed from favorites.',
                'is_favorite' => false,
            ]);
        }

        $this->firestore->add('favorites', [
            'customer_id' => $customerId,
            'flavor_id' => $flavorId,
            'created_at' => now()->toIso8601String(),
        ]);

        return response()->json([
            'success' => true,
            'message' => 'Added to favorites.',
            'is_favorite' => true,
        ]);
    }

    /**
     * Remove a flavor from favorites.
     * DELETE /api/v1/favorites/{flavor_id}
     */
    public function destroy(Request $request, string $flavorId): JsonResponse
    {
        $flavorId = trim($flavorId);
        $flavor = $this->firestore->get('flavors', $flavorId);
        if (! $flavor) {
            return response()->json(['success' => false, 'message' => 'Flavor not found.'], 404);
        }

        $customerId = (string) $request->user()->id;
        $existing = $this->findFavoriteRow($customerId, $flavorId);
        if ($existing) {
            $this->firestore->delete('favorites', (string) $existing['id']);
        }

        return response()->json([
            'success' => true,
            'message' => 'Removed from favorites.',
        ]);
    }

    /**
     * Check if a flavor is in favorites (for UI state).
     * GET /api/v1/favorites/check?flavor_id=...  or  ?flavor_name=...
     */
    public function check(Request $request): JsonResponse
    {
        $flavorIdRaw = trim((string) $request->query('flavor_id', ''));
        $nameRaw = trim((string) $request->query('flavor_name', ''));

        if ($flavorIdRaw === '' && $nameRaw === '') {
            return response()->json([
                'success' => false,
                'message' => 'flavor_id or flavor_name query parameter is required.',
            ], 422);
        }

        $flavor = $this->resolveFlavor($flavorIdRaw, $nameRaw !== '' ? $nameRaw : null);
        if (! $flavor) {
            return response()->json(['success' => false, 'message' => 'Flavor not found.'], 404);
        }

        $flavorId = (string) ($flavor['id'] ?? '');

        $customerId = (string) $request->user()->id;
        $isFavorite = $this->findFavoriteRow($customerId, $flavorId) !== null;

        return response()->json([
            'success' => true,
            'is_favorite' => $isFavorite,
        ]);
    }

    private function findFavoriteRow(string $customerId, string $flavorId): ?array
    {
        $rows = $this->firestore->where('favorites', 'customer_id', $customerId);

        foreach ($rows as $row) {
            if ((string) ($row['flavor_id'] ?? '') === $flavorId) {
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

    /** @param  array<string, mixed>  $row */
    private function ensureStringFlavorId(array $row): array
    {
        if (isset($row['id'])) {
            $row['id'] = (string) $row['id'];
        }

        return $row;
    }
}
