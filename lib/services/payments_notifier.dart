import 'package:flutter/material.dart';
import 'package:phan_mem_quan_ly_can_ho/models/payment_model.dart';
import 'package:phan_mem_quan_ly_can_ho/services/payments_service.dart';

class PaymentsNotifier extends ChangeNotifier {
  final PaymentService _paymentService;

  List<Payment> _payments = [];
  List<Payment> _roomPayments = [];
  bool _isLoading = false;

  PaymentsNotifier(this._paymentService);

  // Getters
  List<Payment> get payments => _payments;
  List<Payment> get roomPayments => _roomPayments;
  bool get isLoading => _isLoading;

  // Safe notifyListeners — won't crash if called during a build
  void _safeNotify() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (hasListeners) notifyListeners();
    });
  }

  // Set full organization payments list
  void setPayments(List<Payment> payments) {
    _payments = payments;
    notifyListeners();
  }

  // Add a new payment and notify listeners
  Future<String?> addPayment(Payment payment) async {
    try {
      final paymentId = await _paymentService.addPayment(payment);

      if (paymentId != null) {
        final newPayment = payment.copyWith(id: paymentId);
        _payments.insert(0, newPayment);
        notifyListeners();
      }

      return paymentId;
    } catch (e) {
      print('Error adding payment in notifier: $e');
      rethrow;
    }
  }

  // Add electricity payment
  Future<String?> addElectricityPayment({
    required String organizationId,
    required String buildingId,
    required String roomId,
    required String tenantId,
    required String tenantName,
    required double startReading,
    required DateTime startDate,
    required double endReading,
    required DateTime endDate,
    required double pricePerUnit,
    required DateTime dueDate,
    String? description,
  }) async {
    try {
      final paymentId = await _paymentService.addElectricityPayment(
        organizationId: organizationId,
        buildingId: buildingId,
        roomId: roomId,
        tenantId: tenantId,
        tenantName: tenantName,
        startReading: startReading,
        startDate: startDate,
        endReading: endReading,
        endDate: endDate,
        pricePerUnit: pricePerUnit,
        dueDate: dueDate,
        description: description,
      );

      if (paymentId != null) {
        await refreshPayments(organizationId);
      }

      return paymentId;
    } catch (e) {
      print('Error adding electricity payment in notifier: $e');
      rethrow;
    }
  }

  // Add water payment
  Future<String?> addWaterPayment({
    required String organizationId,
    required String buildingId,
    required String roomId,
    required String tenantId,
    required String tenantName,
    required double startReading,
    required DateTime startDate,
    required double endReading,
    required DateTime endDate,
    required double pricePerUnit,
    required DateTime dueDate,
    String? description,
  }) async {
    try {
      final paymentId = await _paymentService.addWaterPayment(
        organizationId: organizationId,
        buildingId: buildingId,
        roomId: roomId,
        tenantId: tenantId,
        tenantName: tenantName,
        startReading: startReading,
        startDate: startDate,
        endReading: endReading,
        endDate: endDate,
        pricePerUnit: pricePerUnit,
        dueDate: dueDate,
        description: description,
      );

      if (paymentId != null) {
        await refreshPayments(organizationId);
      }

      return paymentId;
    } catch (e) {
      print('Error adding water payment in notifier: $e');
      rethrow;
    }
  }

  // Add rent payment
  Future<String?> addRentPayment({
    required String organizationId,
    required String buildingId,
    required String roomId,
    required String tenantId,
    required String tenantName,
    required double amount,
    required DateTime startDate,
    required DateTime endDate,
    required DateTime dueDate,
    String? description,
  }) async {
    try {
      final paymentId = await _paymentService.addRentPayment(
        organizationId: organizationId,
        buildingId: buildingId,
        roomId: roomId,
        tenantId: tenantId,
        tenantName: tenantName,
        amount: amount,
        startDate: startDate,
        endDate: endDate,
        dueDate: dueDate,
        description: description,
      );

      if (paymentId != null) {
        await refreshPayments(organizationId);
      }

      return paymentId;
    } catch (e) {
      print('Error adding rent payment in notifier: $e');
      rethrow;
    }
  }

  // Add building rent payment (whole-building expense, no tenant/room)
  Future<String?> addBuildingRentPayment({
    required String organizationId,
    required String buildingId,
    required double amount,
    required DateTime dueDate,
    DateTime? startDate,
    DateTime? endDate,
    String? description,
  }) async {
    try {
      final paymentId = await _paymentService.addBuildingRentPayment(
        organizationId: organizationId,
        buildingId: buildingId,
        amount: amount,
        dueDate: dueDate,
        startDate: startDate,
        endDate: endDate,
        description: description,
      );

      if (paymentId != null) {
        await refreshPayments(organizationId);
      }

      return paymentId;
    } catch (e) {
      print('Error adding building rent payment in notifier: $e');
      rethrow;
    }
  }

  // Generic payment update (used for editing amount/dueDate/description etc.)
  Future<bool> updatePayment(
    String paymentId,
    Map<String, dynamic> data, {
    String? organizationId,
  }) async {
    try {
      final success = await _paymentService.updatePayment(paymentId, data);

      if (success && organizationId != null) {
        await refreshPayments(organizationId);
      }

      return success;
    } catch (e) {
      print('Error updating payment in notifier: $e');
      rethrow;
    }
  }

  // Update payment status in both lists
  Future<void> updatePaymentStatus(String paymentId, PaymentStatus status) async {
    try {
      await _paymentService.updatePaymentStatus(paymentId, status);
      _updatePaymentStatusInList(_payments, paymentId, status);
      _updatePaymentStatusInList(_roomPayments, paymentId, status);
      notifyListeners();
    } catch (e) {
      print('Error updating payment status in notifier: $e');
      rethrow;
    }
  }

  void _updatePaymentStatusInList(
    List<Payment> list,
    String paymentId,
    PaymentStatus status,
  ) {
    final index = list.indexWhere((p) => p.id == paymentId);
    if (index >= 0) {
      list[index] = list[index].copyWith(status: status);
    }
  }

  // Delete payment from both lists
  Future<void> deletePayment(String paymentId) async {
    try {
      await _paymentService.deletePayment(paymentId);
      _payments.removeWhere((p) => p.id == paymentId);
      _roomPayments.removeWhere((p) => p.id == paymentId);
      notifyListeners();
    } catch (e) {
      print('Error deleting payment in notifier: $e');
      rethrow;
    }
  }

  // Refresh organization payments list from database
  Future<void> refreshPayments(String organizationId) async {
    try {
      print('PaymentsNotifier: Refreshing payments for org: $organizationId');
      _payments = await _paymentService.getOrganizationPayments(organizationId);
      print('PaymentsNotifier: Fetched ${_payments.length} payments');
      _safeNotify();
    } catch (e) {
      print('Error refreshing payments in notifier: $e');
      rethrow;
    }
  }

  // Load payments for a specific organization
  Future<void> loadPayments(String organizationId) async {
    try {
      print('PaymentsNotifier: Loading payments for org: $organizationId');
      _payments = await _paymentService.getOrganizationPayments(organizationId);
      print('PaymentsNotifier: Loaded ${_payments.length} payments');
      _safeNotify();
    } catch (e) {
      print('Error loading payments in notifier: $e');
      rethrow;
    }
  }

  // Load payments for a specific room into _roomPayments (does NOT affect _payments)
  Future<void> loadRoomPayments(String roomId, String organizationId) async {
    _isLoading = true;
    _safeNotify();

    try {
      _roomPayments = await _paymentService.getRoomPayments(roomId, organizationId);
    } catch (e) {
      print('Error loading room payments: $e');
      _roomPayments = [];
    } finally {
      _isLoading = false;
      _safeNotify();
    }
  }

  // Refresh payments for a specific room
  Future<void> refreshRoomPayments(String roomId, String organizationId) async {
    await loadRoomPayments(roomId, organizationId);
  }

  // Clear all payments
  void clearPayments() {
    _payments = [];
    _roomPayments = [];
    notifyListeners();
  }
}