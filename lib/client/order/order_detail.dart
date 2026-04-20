import 'package:flutter/material.dart';
import 'package:ice_cream/client/order/order_record.dart';

/// Full-screen order details view showing all order information.
class OrderDetailPage extends StatelessWidget {
  const OrderDetailPage({
    super.key,
    required this.order,
  });

  final OrderRecord order;

  static const String _placeholderAsset = 'lib/client/order/images/mg.png';

  @override
  Widget build(BuildContext context) {
    final isNetworkImage = order.productImageUrl.startsWith('http');

    return Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new, size: 20, color: Colors.black87),
        ),
        title: const Text(
          'Order Details',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusCard(context),
            const SizedBox(height: 16),
            _buildProductCard(context, isNetworkImage),
            const SizedBox(height: 16),
            _buildInfoSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    final statusLabel = _formatStatus(order.status);
    final statusColor = _statusColor(order.status);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            spreadRadius: 1,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Order #${order.transactionId.isNotEmpty ? order.transactionId : order.id}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1C1B1F),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: statusColor, width: 1),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          if (order.createdAtFormatted != null && order.createdAtFormatted!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              order.createdAtFormatted!,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF5B5B5B),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProductCard(BuildContext context, bool isNetworkImage) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            spreadRadius: 1,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: isNetworkImage
                ? Image.network(
                    order.productImageUrl,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Image.asset(
                      _placeholderAsset,
                      width: 80,
                      height: 80,
                      fit: BoxFit.cover,
                    ),
                  )
                : Image.asset(
                    _placeholderAsset,
                    width: 80,
                    height: 80,
                    fit: BoxFit.cover,
                  ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.productName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1C1B1F),
                  ),
                ),
                if (order.productType.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    order.productType,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF5B5B5B),
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  order.gallonSize,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF5B5B5B),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Qty: ${order.quantity}',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF5B5B5B),
                      ),
                    ),
                    Text(
                      order.amountFormatted,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE3001B),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoSection(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            spreadRadius: 1,
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Order information',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1C1B1F),
            ),
          ),
          const SizedBox(height: 14),
          _detailRow('Order ID', '${order.id}'),
          if (order.transactionId.isNotEmpty) _detailRow('Transaction ID', order.transactionId),
          _detailRow('Status', _formatStatus(order.status)),
          if (order.paymentMethod != null && order.paymentMethod!.isNotEmpty)
            _detailRow('Payment', order.paymentMethod!),
          if (order.deliveryDate != null && order.deliveryDate!.isNotEmpty)
            _detailRow('Delivery date', order.deliveryDate!),
          if (order.deliveryTime != null && order.deliveryTime!.isNotEmpty)
            _detailRow('Delivery time', order.deliveryTime!),
          if (order.deliveryAddress != null && order.deliveryAddress!.isNotEmpty)
            _detailRow('Delivery address', order.deliveryAddress!),
        ],
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF5B5B5B),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF1C1B1F),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatStatus(String status) {
    final s = status.trim().toLowerCase();
    if (s.isEmpty) return '—';
    switch (s) {
      case 'pending':
        return 'Pending';
      case 'preparing':
        return 'Preparing';
      case 'assigned':
        return 'Assigned';
      case 'completed':
      case 'delivered':
        return 'Delivered';
      case 'walk-in':
      case 'walk_in':
      case 'walk in':
      case 'walkin':
        return 'Walk-in';
      case 'cancelled':
      case 'canceled':
        return 'Cancelled';
      default:
        return status[0].toUpperCase() + status.substring(1).toLowerCase();
    }
  }

  Color _statusColor(String status) {
    final s = status.trim().toLowerCase();
    if (s == 'cancelled' || s == 'canceled') return const Color(0xFFE3001B);
    if (s == 'pending' || s == 'preparing' || s == 'assigned') return const Color(0xFFFF6805);
    if (s == 'completed' || s == 'delivered' || s.contains('walk')) return const Color(0xFF22B345);
    return const Color(0xFF007CFF);
  }
}
