import 'package:apartment_management_project_2/models/payment_model.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PaymentService {
  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  // ========================================
  // CREATE - Add a new payment
  // ========================================
  Future<String?> addPayment(Payment payment) async {
    try {
      final docRef = await _firestore.collection('payments').add(payment.toMap());
      print('Payment added successfully: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('Error adding payment: $e');
      return null;
    }
  }

  // ========================================
  // CREATE - Create recurring payments (bulk)
  // ========================================
  Future<bool> createRecurringPayments(List<Payment> payments) async {
    try {
      final batch = _firestore.batch();
      
      for (var payment in payments) {
        final docRef = _firestore.collection('payments').doc();
        batch.set(docRef, payment.toMap());
      }
      
      await batch.commit();
      print('Created ${payments.length} recurring payments');
      return true;
    } catch (e) {
      print('Error creating recurring payments: $e');
      return false;
    }
  }

  // ========================================
  // READ - Get payment by ID
  // ========================================
  Future<Payment?> getPaymentById(String paymentId) async {
    try {
      final doc = await _firestore.collection('payments').doc(paymentId).get();
      
      if (!doc.exists) {
        print('Payment not found: $paymentId');
        return null;
      }
      
      return Payment.fromMap(doc.id, doc.data()!);
    } catch (e) {
      print('Error getting payment: $e');
      return null;
    }
  }

  // ========================================
  // READ - Get all payments for a room
  // ========================================
  Future<List<Payment>> getRoomPayments(String roomId) async {
    try {
      final snapshot = await _firestore
          .collection('payments')
          .where('roomId', isEqualTo: roomId)
          .orderBy('dueDate', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => Payment.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      print('Error getting room payments: $e');
      return [];
    }
  }

  // ========================================
  // READ - Get payments by status
  // ========================================
  Future<List<Payment>> getPaymentsByStatus(
    String organizationId,
    PaymentStatus status,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('payments')
          .where('organizationId', isEqualTo: organizationId)
          .where('status', isEqualTo: status.name)
          .orderBy('dueDate', descending: false)
          .get();

      return snapshot.docs
          .map((doc) => Payment.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      print('Error getting payments by status: $e');
      return [];
    }
  }

  // ========================================
  // READ - Get pending payments for a room
  // ========================================
  Future<List<Payment>> getPendingRoomPayments(String roomId) async {
    try {
      final snapshot = await _firestore
          .collection('payments')
          .where('roomId', isEqualTo: roomId)
          .where('status', isEqualTo: 'pending')
          .orderBy('dueDate', descending: false)
          .get();

      return snapshot.docs
          .map((doc) => Payment.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      print('Error getting pending payments: $e');
      return [];
    }
  }

  // ========================================
  // READ - Get overdue payments
  // ========================================
  Future<List<Payment>> getOverduePayments(String organizationId) async {
    try {
      final now = DateTime.now();
      
      final snapshot = await _firestore
          .collection('payments')
          .where('organizationId', isEqualTo: organizationId)
          .where('status', isEqualTo: 'pending')
          .orderBy('dueDate', descending: false)
          .get();

      // Filter overdue payments in memory
      return snapshot.docs
          .map((doc) => Payment.fromMap(doc.id, doc.data()))
          .where((payment) => payment.dueDate.isBefore(now))
          .toList();
    } catch (e) {
      print('Error getting overdue payments: $e');
      return [];
    }
  }

  // ========================================
  // READ - Get payments by tenant
  // ========================================
  Future<List<Payment>> getTenantPayments(String tenantId) async {
    try {
      final snapshot = await _firestore
          .collection('payments')
          .where('tenantId', isEqualTo: tenantId)
          .orderBy('dueDate', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => Payment.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      print('Error getting tenant payments: $e');
      return [];
    }
  }

  // ========================================
  // READ - Get payments by building
  // ========================================
  Future<List<Payment>> getBuildingPayments(String buildingId) async {
    try {
      final snapshot = await _firestore
          .collection('payments')
          .where('buildingId', isEqualTo: buildingId)
          .orderBy('dueDate', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => Payment.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      print('Error getting building payments: $e');
      return [];
    }
  }

  // ========================================
  // READ - Get all payments in an organization
  // ========================================
  Future<List<Payment>> getOrganizationPayments(String organizationId) async {
    try {
      final snapshot = await _firestore
          .collection('payments')
          .where('organizationId', isEqualTo: organizationId)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => Payment.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      print('Error getting organization payments: $e');
      return [];
    }
  }

  // ========================================
  // READ - Get payments by type
  // ========================================
  Future<List<Payment>> getPaymentsByType(
    String organizationId,
    PaymentType type,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('payments')
          .where('organizationId', isEqualTo: organizationId)
          .where('type', isEqualTo: type.name)
          .orderBy('dueDate', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => Payment.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      print('Error getting payments by type: $e');
      return [];
    }
  }

  // ========================================
  // READ - Get payments in date range
  // ========================================
  Future<List<Payment>> getPaymentsInDateRange(
    String organizationId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('payments')
          .where('organizationId', isEqualTo: organizationId)
          .where('dueDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('dueDate', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .orderBy('dueDate', descending: false)
          .get();

      return snapshot.docs
          .map((doc) => Payment.fromMap(doc.id, doc.data()))
          .toList();
    } catch (e) {
      print('Error getting payments in date range: $e');
      return [];
    }
  }

  // ========================================
  // READ - Stream payments (real-time updates)
  // ========================================
  Stream<List<Payment>> streamRoomPayments(String roomId) {
    return _firestore
        .collection('payments')
        .where('roomId', isEqualTo: roomId)
        .orderBy('dueDate', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Payment.fromMap(doc.id, doc.data()))
            .toList());
  }

  Stream<List<Payment>> streamBuildingPayments(String buildingId) {
    return _firestore
        .collection('payments')
        .where('buildingId', isEqualTo: buildingId)
        .orderBy('dueDate', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Payment.fromMap(doc.id, doc.data()))
            .toList());
  }

  Stream<List<Payment>> streamOrganizationPayments(String organizationId) {
    return _firestore
        .collection('payments')
        .where('organizationId', isEqualTo: organizationId)
        .orderBy('dueDate', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Payment.fromMap(doc.id, doc.data()))
            .toList());
  }

  // ========================================
  // UPDATE - Update payment
  // ========================================
  Future<bool> updatePayment(String paymentId, Map<String, dynamic> data) async {
    try {
      await _firestore.collection('payments').doc(paymentId).update(data);
      print('Payment updated successfully: $paymentId');
      return true;
    } catch (e) {
      print('Error updating payment: $e');
      return false;
    }
  }

  // ========================================
  // UPDATE - Mark payment as paid
  // ========================================
  Future<bool> markAsPaid(
    String paymentId, {
    required double paidAmount,
    required PaymentMethod paymentMethod,
    String? transactionId,
    String? receiptNumber,
    String? paidBy,
    String? notes,
  }) async {
    try {
      final payment = await getPaymentById(paymentId);
      if (payment == null) return false;

      final totalDue = payment.totalAmount;
      final newPaidAmount = payment.paidAmount + paidAmount;

      PaymentStatus newStatus;
      if (newPaidAmount >= totalDue) {
        newStatus = PaymentStatus.paid;
      } else {
        newStatus = PaymentStatus.partial;
      }

      return updatePayment(paymentId, {
        'status': newStatus.name,
        'paidAmount': newPaidAmount,
        'paymentMethod': paymentMethod.name,
        'transactionId': transactionId,
        'receiptNumber': receiptNumber,
        'paidAt': Timestamp.now(),
        'paidBy': paidBy,
        'notes': notes,
      });
    } catch (e) {
      print('Error marking payment as paid: $e');
      return false;
    }
  }

  // ========================================
  // UPDATE - Update payment status
  // ========================================
  Future<bool> updatePaymentStatus(
    String paymentId,
    PaymentStatus status,
  ) async {
    return updatePayment(paymentId, {
      'status': status.name,
    });
  }

  // ========================================
  // UPDATE - Add late fee
  // ========================================
  Future<bool> addLateFee(String paymentId, double lateFee) async {
    try {
      final payment = await getPaymentById(paymentId);
      if (payment == null) return false;

      final newLateFee = (payment.lateFee ?? 0) + lateFee;

      return updatePayment(paymentId, {
        'lateFee': newLateFee,
        'status': PaymentStatus.overdue.name,
      });
    } catch (e) {
      print('Error adding late fee: $e');
      return false;
    }
  }

  // ========================================
  // UPDATE - Cancel payment
  // ========================================
  Future<bool> cancelPayment(String paymentId, String? reason) async {
    return updatePayment(paymentId, {
      'status': PaymentStatus.cancelled.name,
      'notes': reason,
    });
  }

  // ========================================
  // UPDATE - Refund payment
  // ========================================
  Future<bool> refundPayment(
    String paymentId,
    double refundAmount,
    String? reason,
  ) async {
    try {
      final payment = await getPaymentById(paymentId);
      if (payment == null) return false;

      final newPaidAmount = payment.paidAmount - refundAmount;

      return updatePayment(paymentId, {
        'status': PaymentStatus.refunded.name,
        'paidAmount': newPaidAmount < 0 ? 0 : newPaidAmount,
        'notes': reason,
      });
    } catch (e) {
      print('Error refunding payment: $e');
      return false;
    }
  }

  // ========================================
  // DELETE - Delete a payment
  // ========================================
  Future<bool> deletePayment(String paymentId) async {
    try {
      await _firestore.collection('payments').doc(paymentId).delete();
      print('Payment deleted successfully: $paymentId');
      return true;
    } catch (e) {
      print('Error deleting payment: $e');
      return false;
    }
  }

  // ========================================
  // DELETE - Delete all room payments
  // ========================================
  Future<bool> deleteAllRoomPayments(String roomId) async {
    try {
      final snapshot = await _firestore
          .collection('payments')
          .where('roomId', isEqualTo: roomId)
          .get();

      final batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      
      await batch.commit();
      print('Deleted ${snapshot.docs.length} payments from room');
      return true;
    } catch (e) {
      print('Error deleting room payments: $e');
      return false;
    }
  }

  // ========================================
  // UTILITY - Calculate total amount due
  // ========================================
  Future<double> calculateTotalDue(String roomId) async {
    try {
      final payments = await getPendingRoomPayments(roomId);
      return payments.fold<double>(0.0, (sum, payment) => sum + payment.remainingAmount);
    } catch (e) {
      print('Error calculating total due: $e');
      return 0.0;
    }
  }

  // ========================================
  // UTILITY - Calculate total paid amount
  // ========================================
  Future<double> calculateTotalPaid(
    String organizationId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      final payments = await getPaymentsInDateRange(
        organizationId,
        startDate,
        endDate,
      );
      
      return payments
          .where((p) => p.status == PaymentStatus.paid)
          .fold<double>(0.0, (sum, payment) => sum + payment.paidAmount);
    } catch (e) {
      print('Error calculating total paid: $e');
      return 0.0;
    }
  }

  // ========================================
  // UTILITY - Get payment statistics
  // ========================================
  Future<Map<String, dynamic>> getPaymentStatistics(
    String organizationId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('payments')
          .where('organizationId', isEqualTo: organizationId)
          .get();

      final payments = snapshot.docs
          .map((doc) => Payment.fromMap(doc.id, doc.data()))
          .toList();

      final now = DateTime.now();
      final totalAmount = payments.fold<double>(0.0, (sum, p) => sum + p.amount);
      final totalPaid = payments
          .where((p) => p.status == PaymentStatus.paid)
          .fold<double>(0.0, (sum, p) => sum + p.paidAmount);
      final totalPending = payments
          .where((p) => p.status == PaymentStatus.pending)
          .fold<double>(0.0, (sum, p) => sum + p.remainingAmount);
      final totalOverdue = payments
          .where((p) => p.dueDate.isBefore(now) && p.status == PaymentStatus.pending)
          .fold<double>(0.0, (sum, p) => sum + p.remainingAmount);

      return {
        'totalPayments': payments.length,
        'totalAmount': totalAmount,
        'totalPaid': totalPaid,
        'totalPending': totalPending,
        'totalOverdue': totalOverdue,
        'pendingCount': payments.where((p) => p.status == PaymentStatus.pending).length,
        'paidCount': payments.where((p) => p.status == PaymentStatus.paid).length,
        'overdueCount': payments
            .where((p) => p.dueDate.isBefore(now) && p.status == PaymentStatus.pending)
            .length,
      };
    } catch (e) {
      print('Error getting payment statistics: $e');
      return {};
    }
  }

  // ========================================
  // UTILITY - Get revenue by type
  // ========================================
  Future<Map<PaymentType, double>> getRevenueByType(
    String organizationId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      final payments = await getPaymentsInDateRange(
        organizationId,
        startDate,
        endDate,
      );

      final revenue = <PaymentType, double>{};
      for (var payment in payments.where((p) => p.status == PaymentStatus.paid)) {
        revenue[payment.type] = (revenue[payment.type] ?? 0) + payment.paidAmount;
      }

      return revenue;
    } catch (e) {
      print('Error getting revenue by type: $e');
      return {};
    }
  }

  // ========================================
  // UTILITY - Auto-update overdue payments
  // ========================================
  Future<int> updateOverduePayments(String organizationId) async {
    try {
      final now = DateTime.now();
      
      final snapshot = await _firestore
          .collection('payments')
          .where('organizationId', isEqualTo: organizationId)
          .where('status', isEqualTo: 'pending')
          .get();

      final batch = _firestore.batch();
      int count = 0;

      for (var doc in snapshot.docs) {
        final payment = Payment.fromMap(doc.id, doc.data());
        if (payment.dueDate.isBefore(now)) {
          batch.update(doc.reference, {'status': PaymentStatus.overdue.name});
          count++;
        }
      }

      if (count > 0) {
        await batch.commit();
        print('Updated $count overdue payments');
      }

      return count;
    } catch (e) {
      print('Error updating overdue payments: $e');
      return 0;
    }
  }

  // ========================================
  // UTILITY - Generate monthly rent payments
  // ========================================
  Future<bool> generateMonthlyRentPayments(
    String organizationId,
    String buildingId,
    String roomId,
    String tenantId,
    String tenantName,
    double monthlyRent,
    DateTime startDate,
    int numberOfMonths,
  ) async {
    try {
      final payments = <Payment>[];
      
      for (int i = 0; i < numberOfMonths; i++) {
        final billingStart = DateTime(
          startDate.year,
          startDate.month + i,
          startDate.day,
        );
        final billingEnd = DateTime(
          startDate.year,
          startDate.month + i + 1,
          startDate.day - 1,
        );
        final dueDate = DateTime(
          startDate.year,
          startDate.month + i + 1,
          5, // Due on 5th of next month
        );

        payments.add(Payment(
          id: '',
          organizationId: organizationId,
          buildingId: buildingId,
          roomId: roomId,
          tenantId: tenantId,
          tenantName: tenantName,
          type: PaymentType.rent,
          status: PaymentStatus.pending,
          amount: monthlyRent,
          dueDate: dueDate,
          billingStartDate: billingStart,
          billingEndDate: billingEnd,
          createdAt: DateTime.now(),
          isRecurring: true,
        ));
      }

      return await createRecurringPayments(payments);
    } catch (e) {
      print('Error generating monthly rent payments: $e');
      return false;
    }
  }
}