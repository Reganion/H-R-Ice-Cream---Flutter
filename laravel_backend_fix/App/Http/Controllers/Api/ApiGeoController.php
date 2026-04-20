<?php

namespace App\Http\Controllers\Api;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use App\Services\DeliveryService;
use App\Models\Order;
use App\Models\Driver;
use App\Models\RiderLocation;
use App\Events\RiderLocationUpdated;

class ApiGeoController extends Controller
{
    protected $deliveryService;

    public function __construct(DeliveryService $deliveryService) 
    {
        $this->deliveryService = $deliveryService;
    }

    public function geocodeOrderAddress($orderId)
    {
        $order = Order::findOrFail($orderId);
        $address = $order->delivery_address;

        $coords = $this->deliveryService->geocodeAddress($address);

        return response()->json([
            'order_id' => $order->id,
            'lat' => $coords['lat'],
            'lng' => $coords['lng'],
        ]);
    }

    public function updateLocation(Request $request) {
        $data = $request->validate([
            'driver_id' => 'required|exists:drivers,id',
            'order_id'  => 'nullable|exists:orders,id',
            'lat'       => 'required|numeric',
            'lng'       => 'required|numeric',
        ]);

        $driver = Driver::find($data['driver_id']);
        
        $driver->update([
            'current_lat' => $data['lat'],
            'current_lng' => $data['lng'],
            'last_updated' => now()
        ]);

        $lastLocation = RiderLocation::where('driver_id', $driver->id)->latest()->first();
        
        $saveHistory = false;

        if(!$lastLocation) {
            $saveHistory = true;
        } else {
            $distance = $this->deliveryService->calculateDistance(
                $lastLocation->lat,
                $lastLocation->lng,
                $data['lat'],
                $data['lng']
            );

            $saveHistory = $this->deliveryService->isSignificantMovement($distance);
        }

        if($saveHistory) {
            RiderLocation::create([
                'driver_id' => $driver->id,
                'order_id' => $data['order_id'] ?? null,
                'lat' => $data['lat'],
                'lng' => $data['lng'],
            ]);
        }

        // socket connection start
        broadcast(new RiderLocationUpdated($driver));

        return response()->json(['success' => true], 200);
    }


}
