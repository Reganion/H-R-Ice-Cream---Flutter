<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use App\Services\FirestoreService;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Collection;

class ApiFlavorController extends Controller
{
    public function __construct(private FirestoreService $firestore)
    {
    }

    /**
     * Best Sellers: top 5 flavors by completed order count (Firestore `orders` + `flavors`).
     * GET /api/v1/best-sellers
     */
    public function bestSellers(): JsonResponse
    {
        $orders = collect($this->firestore->all('orders'));
        $completed = $orders->filter(fn (array $o) => strtolower(trim((string) ($o['status'] ?? ''))) === 'completed');
        $counts = $completed
            ->groupBy(fn (array $o) => trim((string) ($o['product_name'] ?? '')))
            ->map(fn (Collection $group) => $group->count())
            ->sortDesc();

        $topNames = $counts->keys()->filter(fn ($n) => $n !== '')->take(5)->values();
        $allFlavors = collect($this->firestore->all('flavors'));

        $bestSellers = $topNames->map(function (string $name) use ($allFlavors) {
            return $allFlavors->first(fn (array $f) => strcasecmp(trim((string) ($f['name'] ?? '')), $name) === 0);
        })->filter()->values()->all();

        return response()->json([
            'success' => true,
            'data' => array_map(fn (array $f) => $this->ensureStringIds($f), $bestSellers),
        ]);
    }

    /**
     * Popular: top 5 flavors by feedback count, else by completed orders (skip 1st), else latest flavors.
     * GET /api/v1/popular
     */
    public function popular(): JsonResponse
    {
        $allFlavors = collect($this->firestore->all('flavors'));

        $feedbackRows = collect($this->firestore->all('feedback'));
        $popularFlavors = collect();

        if ($feedbackRows->isNotEmpty()) {
            $byFlavor = $feedbackRows
                ->filter(fn (array $f) => ! empty($f['flavor_id']))
                ->groupBy(fn (array $f) => (string) $f['flavor_id'])
                ->map(fn (Collection $group) => $group->count())
                ->sortDesc();

            $popularFlavors = $byFlavor->keys()->take(5)->map(function (string $id) {
                return $this->firestore->get('flavors', $id);
            })->filter()->values();
        }

        if ($popularFlavors->isEmpty()) {
            $orders = collect($this->firestore->all('orders'));
            $completed = $orders->filter(fn (array $o) => strtolower(trim((string) ($o['status'] ?? ''))) === 'completed');
            $counts = $completed
                ->groupBy(fn (array $o) => trim((string) ($o['product_name'] ?? '')))
                ->map(fn (Collection $group) => $group->count())
                ->sortDesc();

            $names = $counts->keys()->filter(fn ($n) => $n !== '')->values();
            $slice = $names->slice(1, 5);
            $popularFlavors = $slice->map(function (string $name) use ($allFlavors) {
                return $allFlavors->first(fn (array $f) => strcasecmp(trim((string) ($f['name'] ?? '')), $name) === 0);
            })->filter()->values();
        }

        if ($popularFlavors->isEmpty()) {
            $popularFlavors = $allFlavors
                ->sortByDesc(fn (array $f) => (string) ($f['created_at'] ?? ''))
                ->take(5)
                ->values();
        }

        return response()->json([
            'success' => true,
            'data' => $popularFlavors->map(fn (array $f) => $this->ensureStringIds($f))->all(),
        ]);
    }

    /**
     * List all flavors (for Flutter).
     * GET /api/v1/flavors
     */
    public function index(): JsonResponse
    {
        $flavors = collect($this->firestore->all('flavors'))
            ->sortByDesc(fn (array $f) => (string) ($f['created_at'] ?? ''))
            ->values()
            ->map(fn (array $f) => $this->ensureStringIds($f))
            ->all();

        return response()->json([
            'success' => true,
            'data' => $flavors,
        ]);
    }

    /**
     * Single flavor by id (Firestore document id).
     */
    public function show(string $id): JsonResponse
    {
        $flavor = $this->firestore->get('flavors', $id);
        if (! $flavor) {
            return response()->json(['success' => false, 'message' => 'Flavor not found.'], 404);
        }

        return response()->json(['success' => true, 'data' => $this->ensureStringIds($flavor)]);
    }

    /**
     * List gallon sizes (for Flutter).
     */
    public function gallons(): JsonResponse
    {
        $gallons = collect($this->firestore->all('gallons'))
            ->sortBy(fn (array $g) => (float) ($g['size'] ?? 0))
            ->values()
            ->map(fn (array $g) => $this->ensureStringIds($g))
            ->all();

        return response()->json(['success' => true, 'data' => $gallons]);
    }

    /**
     * Firestore document ids must stay strings in JSON (Flutter must not parse them as int).
     */
    private function ensureStringIds(array $row): array
    {
        if (isset($row['id'])) {
            $row['id'] = (string) $row['id'];
        }

        return $row;
    }
}
