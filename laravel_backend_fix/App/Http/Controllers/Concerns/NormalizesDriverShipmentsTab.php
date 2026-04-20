<?php

namespace App\Http\Controllers\Concerns;

use Illuminate\Http\Request;

/**
 * Ensures `tab` is always a scalar string for GET /driver/shipments.
 *
 * Laravel can expose `tab` as an array when the query string repeats `tab` or
 * uses `tab[]`, which then breaks `mapShipmentRow(..., string $tab, ...)`.
 */
trait NormalizesDriverShipmentsTab
{
    protected function normalizeDriverShipmentsTab(Request $request): string
    {
        $raw = $request->query('tab', 'incoming');
        if (is_array($raw)) {
            $first = reset($raw);
            $raw = $first !== false ? $first : 'incoming';
        }

        $tab = strtolower(trim((string) $raw));
        if (! in_array($tab, ['incoming', 'accepted', 'completed'], true)) {
            $tab = 'incoming';
        }

        return $tab;
    }
}
