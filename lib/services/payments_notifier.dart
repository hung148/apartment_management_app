import 'package:flutter/material.dart';
import 'package:apartment_management_project_2/models/payment_model.dart';
import 'package:apartment_management_project_2/services/payments_service.dart';

class PaymentsNotifier extends ChangeNotifier {
  final PaymentService _paymentService;
  
  List<Payment> _payments = [];
  bool _isLoading = false;

  PaymentsNotifier(this._paymentService);
  
  // Getter for payments list
  List<Payment> get payments => _payments;
  bool get isLoading => _isLoading;
  
  // Set payments list (useful when loading from database)
  void setPayments(List<Payment> payments) {
    _payments = payments;
    notifyListeners();
  }
  
  // Add a new payment and notify listeners
  Future<String?> addPayment(Payment payment) async {
    try {
      final paymentId = await _paymentService.addPayment(payment);
      
      if (paymentId != null) {
        // Create payment with the returned ID
        final newPayment = Payment(
          id: paymentId,
          organizationId: payment.organizationId,
          buildingId: payment.buildingId,
          roomId: payment.roomId,
          tenantId: payment.tenantId,
          tenantName: payment.tenantName,
          type: payment.type,
          status: payment.status,
          amount: payment.amount,
          paidAmount: payment.paidAmount,
          currency: payment.currency,
          paymentMethod: payment.paymentMethod,
          transactionId: payment.transactionId,
          receiptNumber: payment.receiptNumber,
          dueDate: payment.dueDate,
          paidAt: payment.paidAt,
          paidBy: payment.paidBy,
          billingStartDate: payment.billingStartDate,
          billingEndDate: payment.billingEndDate,
          waterStartReading: payment.waterStartReading,
          waterStartDate: payment.waterStartDate,
          waterEndReading: payment.waterEndReading,
          waterEndDate: payment.waterEndDate,
          waterPricePerUnit: payment.waterPricePerUnit,
          electricityStartReading: payment.electricityStartReading,
          electricityStartDate: payment.electricityStartDate,
          electricityEndReading: payment.electricityEndReading,
          electricityEndDate: payment.electricityEndDate,
          electricityPricePerUnit: payment.electricityPricePerUnit,
          description: payment.description,
          notes: payment.notes,
          metadata: payment.metadata,
          lateFee: payment.lateFee,
          isRecurring: payment.isRecurring,
          recurringParentId: payment.recurringParentId,
          createdAt: payment.createdAt,
        );
        
        // Add to local list and notify listeners
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
        // Reload payments to get the full payment object
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
        // Reload payments to get the full payment object
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
        // Reload payments to get the full payment object
        await refreshPayments(organizationId);
      }
      
      return paymentId;
    } catch (e) {
      print('Error adding rent payment in notifier: $e');
      rethrow;
    }
  }
  
  // Update payment status
  Future<void> updatePaymentStatus(String paymentId, PaymentStatus status) async {
    try {
      await _paymentService.updatePaymentStatus(paymentId, status);
      
      // Update in local list
      final index = _payments.indexWhere((p) => p.id == paymentId);
      if (index >= 0) {
        _payments[index] = Payment(
          id: _payments[index].id,
          organizationId: _payments[index].organizationId,
          buildingId: _payments[index].buildingId,
          roomId: _payments[index].roomId,
          tenantId: _payments[index].tenantId,
          tenantName: _payments[index].tenantName,
          type: _payments[index].type,
          status: status,
          amount: _payments[index].amount,
          paidAmount: _payments[index].paidAmount,
          currency: _payments[index].currency,
          paymentMethod: _payments[index].paymentMethod,
          transactionId: _payments[index].transactionId,
          receiptNumber: _payments[index].receiptNumber,
          dueDate: _payments[index].dueDate,
          paidAt: _payments[index].paidAt,
          paidBy: _payments[index].paidBy,
          billingStartDate: _payments[index].billingStartDate,
          billingEndDate: _payments[index].billingEndDate,
          waterStartReading: _payments[index].waterStartReading,
          waterStartDate: _payments[index].waterStartDate,
          waterEndReading: _payments[index].waterEndReading,
          waterEndDate: _payments[index].waterEndDate,
          waterPricePerUnit: _payments[index].waterPricePerUnit,
          electricityStartReading: _payments[index].electricityStartReading,
          electricityStartDate: _payments[index].electricityStartDate,
          electricityEndReading: _payments[index].electricityEndReading,
          electricityEndDate: _payments[index].electricityEndDate,
          electricityPricePerUnit: _payments[index].electricityPricePerUnit,
          description: _payments[index].description,
          notes: _payments[index].notes,
          metadata: _payments[index].metadata,
          lateFee: _payments[index].lateFee,
          isRecurring: _payments[index].isRecurring,
          recurringParentId: _payments[index].recurringParentId,
          createdAt: _payments[index].createdAt,
        );
        notifyListeners();
      }
    } catch (e) {
      print('Error updating payment status in notifier: $e');
      rethrow;
    }
  }
  
  // Delete payment
  Future<void> deletePayment(String paymentId) async {
    try {
      await _paymentService.deletePayment(paymentId);
      
      // Remove from local list
      _payments.removeWhere((p) => p.id == paymentId);
      notifyListeners();
    } catch (e) {
      print('Error deleting payment in notifier: $e');
      rethrow;
    }
  }
  
  // Refresh payments list from database
  Future<void> refreshPayments(String organizationId) async {
    try {
      print('PaymentsNotifier: Refreshing payments for org: $organizationId');
      final updatedPayments = await _paymentService.getOrganizationPayments(organizationId);
      print('PaymentsNotifier: Fetched ${updatedPayments.length} payments');
      _payments = updatedPayments;
      notifyListeners();
      print('PaymentsNotifier: Notified listeners');
    } catch (e) {
      print('Error refreshing payments in notifier: $e');
      rethrow;
    }
  }
  
  // Load payments for a specific organization
  Future<void> loadPayments(String organizationId) async {
    try {
      print('PaymentsNotifier: Loading payments for org: $organizationId');
      final loadedPayments = await _paymentService.getOrganizationPayments(organizationId);
      print('PaymentsNotifier: Loaded ${loadedPayments.length} payments');
      _payments = loadedPayments;
      notifyListeners();
      print('PaymentsNotifier: Notified listeners after load');
    } catch (e) {
      print('Error loading payments in notifier: $e');
      rethrow;
    }
  }

  // Load payments for a specific room
  Future<void> loadRoomPayments(String roomId) async {
    _isLoading = true;
    notifyListeners();

    try {
      _payments = await _paymentService.getRoomPayments(roomId);
    } catch (e) {
      print('Error loading room payments: $e');
      _payments = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // Refresh payments for a specific room
  Future<void> refreshRoomPayments(String roomId) async {
    await loadRoomPayments(roomId);
  }

  // Clear all payments
  void clearPayments() {
    _payments = [];
    notifyListeners();
  }
}
