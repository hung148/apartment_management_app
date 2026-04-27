import 'package:phan_mem_quan_ly_can_ho/models/payment_model.dart';
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
  // CREATE - Add electricity payment with meter readings
  // ========================================
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
      final usage = endReading - startReading;
      final amount = usage * pricePerUnit;

      final payment = Payment(
        id: '',
        organizationId: organizationId,
        buildingId: buildingId,
        roomId: roomId,
        tenantId: tenantId,
        tenantName: tenantName,
        type: PaymentType.electricity,
        status: PaymentStatus.pending,
        amount: amount,
        dueDate: dueDate,
        electricityStartReading: startReading,
        electricityStartDate: startDate,
        electricityEndReading: endReading,
        electricityEndDate: endDate,
        electricityPricePerUnit: pricePerUnit,
        description: description ?? 'Tiền điện từ ${_formatDate(startDate)} đến ${_formatDate(endDate)}',
        createdAt: DateTime.now(),
      );

      return await addPayment(payment);
    } catch (e) {
      print('Error adding electricity payment: $e');
      return null;
    }
  }

  // ========================================
  // CREATE - Add water payment with meter readings
  // ========================================
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
      final usage = endReading - startReading;
      final amount = usage * pricePerUnit;

      final payment = Payment(
        id: '',
        organizationId: organizationId,
        buildingId: buildingId,
        roomId: roomId,
        tenantId: tenantId,
        tenantName: tenantName,
        type: PaymentType.water,
        status: PaymentStatus.pending,
        amount: amount,
        dueDate: dueDate,
        billingStartDate: startDate,
        billingEndDate: endDate,
        waterStartReading: startReading,
        waterStartDate: startDate,
        waterEndReading: endReading,
        waterEndDate: endDate,
        waterPricePerUnit: pricePerUnit,
        description: description ?? 'Tiền nước từ ${_formatDate(startDate)} đến ${_formatDate(endDate)}',
        createdAt: DateTime.now(),
      );

      return await addPayment(payment);
    } catch (e) {
      print('Error adding water payment: $e');
      return null;
    }
  }

  // ========================================
  // CREATE - Add rent payment with period
  // ========================================
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
      final payment = Payment(
        id: '',
        organizationId: organizationId,
        buildingId: buildingId,
        roomId: roomId,
        tenantId: tenantId,
        tenantName: tenantName,
        type: PaymentType.rent,
        status: PaymentStatus.pending,
        amount: amount,
        dueDate: dueDate,
        billingStartDate: startDate,
        billingEndDate: endDate,
        description: description ?? 'Tiền thuê từ ${_formatDate(startDate)} đến ${_formatDate(endDate)}',
        createdAt: DateTime.now(),
      );

      return await addPayment(payment);
    } catch (e) {
      print('Error adding rent payment: $e');
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
  // CREATE - Add combined payment with utilities and fees
  // ========================================
  Future<String?> addCombinedPayment({
    required String organizationId,
    required String buildingId,
    required String roomId,
    required String tenantId,
    required String tenantName,
    required DateTime startDate,
    required DateTime endDate,
    required DateTime dueDate,
    double? rent,
    double? electricityAmount,
    double? waterAmount,
    double? internetFee,
    double? cableTVFee,
    double? hotWaterFee,
    double? hotWaterPercent,
    double? managementFee,
    double? taxAmount,
    double? electricityStartReading,
    double? electricityEndReading,
    double? electricityPricePerUnit,
    double? waterStartReading,
    double? waterEndReading,
    double? waterPricePerUnit,
    String? description,
  }) async {
    try {
      // Calculate electricity amount if readings provided
      double? finalElectricityAmount = electricityAmount;
      if (electricityStartReading != null && 
          electricityEndReading != null && 
          electricityPricePerUnit != null) {
        final usage = electricityEndReading - electricityStartReading;
        finalElectricityAmount = usage * electricityPricePerUnit;
      }

      // Calculate water amount if readings provided
      double? finalWaterAmount = waterAmount;
      if (waterStartReading != null && 
          waterEndReading != null && 
          waterPricePerUnit != null) {
        final usage = waterEndReading - waterStartReading;
        finalWaterAmount = usage * waterPricePerUnit;
      }

      // Calculate total amount (without tax)
      double totalAmount = 0;
      if (rent != null) totalAmount += rent;
      if (finalElectricityAmount != null) totalAmount += finalElectricityAmount;
      if (finalWaterAmount != null) totalAmount += finalWaterAmount;
      if (internetFee != null) totalAmount += internetFee;
      if (cableTVFee != null) totalAmount += cableTVFee;
      if (hotWaterFee != null) totalAmount += hotWaterFee;
      if (managementFee != null) totalAmount += managementFee;

      final payment = Payment(
        id: '',
        organizationId: organizationId,
        buildingId: buildingId,
        roomId: roomId,
        tenantId: tenantId,
        tenantName: tenantName,
        type: PaymentType.rent,
        status: PaymentStatus.pending,
        amount: totalAmount,
        dueDate: dueDate,
        billingStartDate: startDate,
        billingEndDate: endDate,
        electricityStartReading: electricityStartReading,
        electricityStartDate: startDate,
        electricityEndReading: electricityEndReading,
        electricityEndDate: endDate,
        electricityPricePerUnit: electricityPricePerUnit,
        waterStartReading: waterStartReading,
        waterStartDate: startDate,
        waterEndReading: waterEndReading,
        waterEndDate: endDate,
        waterPricePerUnit: waterPricePerUnit,
        internetFee: internetFee,
        cableTVFee: cableTVFee,
        hotWaterFee: hotWaterFee,
        hotWaterPercent: hotWaterPercent,
        managementFee: managementFee,
        taxAmount: taxAmount,
        description: description ?? 'Hóa đơn tổng hợp từ ${_formatDate(startDate)} đến ${_formatDate(endDate)}',
        createdAt: DateTime.now(),
      );

      return await addPayment(payment);
    } catch (e) {
      print('Error adding combined payment: $e');
      return null;
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
  Future<List<Payment>> getRoomPayments(String roomId, String organizationId) async {
    try {
      final snapshot = await _firestore
          .collection('payments')
          .where('organizationId', isEqualTo: organizationId)
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
  Future<List<Payment>> getPendingRoomPayments(String organizationId, String roomId) async {
    try {
      final snapshot = await _firestore
          .collection('payments')
          .where('organizationId', isEqualTo: organizationId)
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
  Future<List<Payment>> getTenantPayments(String organizationId, String tenantId) async {
    try {
      final snapshot = await _firestore
          .collection('payments')
          .where('organizationId', isEqualTo: organizationId)
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
  Future<List<Payment>> getBuildingPayments(String organizationId, String buildingId) async {
    try {
      final snapshot = await _firestore
          .collection('payments')
          .where('organizationId', isEqualTo: organizationId)
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
  // READ - Get last electricity reading for a room
  // ========================================
  Future<Map<String, dynamic>?> getLastElectricityReading(String organizationId, String roomId) async {
    try {
      final snapshot = await _firestore
          .collection('payments')
          .where('organizationId', isEqualTo: organizationId)
          .where('roomId', isEqualTo: roomId)
          .where('type', isEqualTo: 'electricity')
          .orderBy('electricityEndDate', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;

      final payment = Payment.fromMap(snapshot.docs.first.id, snapshot.docs.first.data());
      
      return {
        'reading': payment.electricityEndReading,
        'date': payment.electricityEndDate,
        'pricePerUnit': payment.electricityPricePerUnit,
      };
    } catch (e) {
      print('Error getting last electricity reading: $e');
      return null;
    }
  }

  // ========================================
  // READ - Get last water reading for a room
  // ========================================
  Future<Map<String, dynamic>?> getLastWaterReading(String organizationId, String roomId) async {
    try {
      final snapshot = await _firestore
          .collection('payments')
          .where('organizationId', isEqualTo: organizationId)
          .where('roomId', isEqualTo: roomId)
          .where('type', isEqualTo: 'water')
          .orderBy('waterEndDate', descending: true)
          .limit(1)
          .get();

      if (snapshot.docs.isEmpty) return null;

      final payment = Payment.fromMap(snapshot.docs.first.id, snapshot.docs.first.data());
      
      return {
        'reading': payment.waterEndReading,
        'date': payment.waterEndDate,
        'pricePerUnit': payment.waterPricePerUnit,
      };
    } catch (e) {
      print('Error getting last water reading: $e');
      return null;
    }
  }

  // ========================================
  // READ - Stream payments (real-time updates)
  // ========================================
  Stream<List<Payment>> streamRoomPayments(String organizationId, String roomId) {
    return _firestore
        .collection('payments')
        .where('organizationId', isEqualTo: organizationId)
        .where('roomId', isEqualTo: roomId)
        .orderBy('dueDate', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => Payment.fromMap(doc.id, doc.data()))
            .toList());
  }

  Stream<List<Payment>> streamBuildingPayments(String organizationId, String buildingId) {
    return _firestore
        .collection('payments')
        .where('organizationId', isEqualTo: organizationId)
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
  // UPDATE - Update electricity meter readings
  // ========================================
  Future<bool> updateElectricityReadings({
    required String paymentId,
    double? startReading,
    DateTime? startDate,
    double? endReading,
    DateTime? endDate,
    double? pricePerUnit,
  }) async {
    try {
      final payment = await getPaymentById(paymentId);
      if (payment == null || payment.type != PaymentType.electricity) {
        print('Payment not found or not an electricity payment');
        return false;
      }

      final Map<String, dynamic> updates = {};
      
      if (startReading != null) updates['electricityStartReading'] = startReading;
      if (startDate != null) updates['electricityStartDate'] = Timestamp.fromDate(startDate);
      if (endReading != null) updates['electricityEndReading'] = endReading;
      if (endDate != null) updates['electricityEndDate'] = Timestamp.fromDate(endDate);
      if (pricePerUnit != null) updates['electricityPricePerUnit'] = pricePerUnit;

      // Recalculate amount if readings changed
      final newStartReading = startReading ?? payment.electricityStartReading ?? 0;
      final newEndReading = endReading ?? payment.electricityEndReading ?? 0;
      final newPricePerUnit = pricePerUnit ?? payment.electricityPricePerUnit ?? 0;
      
      if (startReading != null || endReading != null || pricePerUnit != null) {
        final usage = newEndReading - newStartReading;
        final newAmount = usage * newPricePerUnit;
        updates['amount'] = newAmount;
      }

      return await updatePayment(paymentId, updates);
    } catch (e) {
      print('Error updating electricity readings: $e');
      return false;
    }
  }

  // ========================================
  // UPDATE - Update water meter readings
  // ========================================
  Future<bool> updateWaterReadings({
    required String paymentId,
    double? startReading,
    DateTime? startDate,
    double? endReading,
    DateTime? endDate,
    double? pricePerUnit,
  }) async {
    try {
      final payment = await getPaymentById(paymentId);
      if (payment == null || payment.type != PaymentType.water) {
        print('Payment not found or not a water payment');
        return false;
      }

      final Map<String, dynamic> updates = {};
      
      if (startReading != null) updates['waterStartReading'] = startReading;
      if (startDate != null) updates['waterStartDate'] = Timestamp.fromDate(startDate);
      if (endReading != null) updates['waterEndReading'] = endReading;
      if (endDate != null) updates['waterEndDate'] = Timestamp.fromDate(endDate);
      if (pricePerUnit != null) updates['waterPricePerUnit'] = pricePerUnit;

      // Recalculate amount if readings changed
      final newStartReading = startReading ?? payment.waterStartReading ?? 0;
      final newEndReading = endReading ?? payment.waterEndReading ?? 0;
      final newPricePerUnit = pricePerUnit ?? payment.waterPricePerUnit ?? 0;
      
      if (startReading != null || endReading != null || pricePerUnit != null) {
        final usage = newEndReading - newStartReading;
        final newAmount = usage * newPricePerUnit;
        updates['amount'] = newAmount;
      }

      return await updatePayment(paymentId, updates);
    } catch (e) {
      print('Error updating water readings: $e');
      return false;
    }
  }

  // ========================================
  // UPDATE - Mark payment as paid (with combined payment support)
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

      final totalDue = payment.totalWithAllFees;
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
  Future<bool> deleteAllRoomPayments(String organizationId, String roomId) async {
    try {
      final snapshot = await _firestore
          .collection('payments')
          .where('organizationId', isEqualTo: organizationId)
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
  // UTILITY - Calculate total amount due (with combined payment support)
  // ========================================
  Future<double> calculateTotalDue(String organizationId, String roomId) async {
    try {
      final payments = await getPendingRoomPayments(organizationId, roomId);
      return payments.fold<double>(0.0, (sum, payment) => sum + payment.remainingAmount);
    } catch (e) {
      print('Error calculating total due: $e');
      return 0.0;
    }
  }

  // ========================================
  // UTILITY - Calculate combined fees breakdown
  // ========================================
  Future<Map<String, double>> calculateCombinedFeesBreakdown(
    String organizationId,
    String roomId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('payments')
          .where('organizationId', isEqualTo: organizationId)
          .where('roomId', isEqualTo: roomId)
          .where('billingStartDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startDate))
          .where('billingEndDate', isLessThanOrEqualTo: Timestamp.fromDate(endDate))
          .get();

      final payments = snapshot.docs
          .map((doc) => Payment.fromMap(doc.id, doc.data()))
          .toList();

      double totalInternetFee = 0;
      double totalCableTVFee = 0;
      double totalHotWaterFee = 0;
      double totalManagementFee = 0;

      for (var payment in payments) {
        if (payment.internetFee != null) totalInternetFee += payment.internetFee!;
        if (payment.cableTVFee != null) totalCableTVFee += payment.cableTVFee!;
        if (payment.hotWaterFee != null) totalHotWaterFee += payment.hotWaterFee!;
        if (payment.managementFee != null) totalManagementFee += payment.managementFee!;
      }

      return {
        'internet': totalInternetFee,
        'cableTV': totalCableTVFee,
        'hotWater': totalHotWaterFee,
        'management': totalManagementFee,
      };
    } catch (e) {
      print('Error calculating combined fees: $e');
      return {};
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
  // UTILITY - Get payment statistics (with combined payment support)
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
      final totalAmount = payments.fold<double>(0.0, (sum, p) => sum + p.totalWithAllFees);
      final totalPaid = payments
          .where((p) => p.status == PaymentStatus.paid)
          .fold<double>(0.0, (sum, p) => sum + p.paidAmount);
      final totalPending = payments
          .where((p) => p.status == PaymentStatus.pending)
          .fold<double>(0.0, (sum, p) => sum + p.remainingAmount);
      final totalOverdue = payments
          .where((p) => p.dueDate.isBefore(now) && p.status == PaymentStatus.pending)
          .fold<double>(0.0, (sum, p) => sum + p.remainingAmount);

      // Calculate total additional fees
      double totalInternetFee = 0;
      double totalCableTVFee = 0;
      double totalHotWaterFee = 0;
      double totalManagementFee = 0;

      for (var payment in payments) {
        if (payment.internetFee != null) totalInternetFee += payment.internetFee!;
        if (payment.cableTVFee != null) totalCableTVFee += payment.cableTVFee!;
        if (payment.hotWaterFee != null) totalHotWaterFee += payment.hotWaterFee!;
        if (payment.managementFee != null) totalManagementFee += payment.managementFee!;
      }

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
        'totalInternetFee': totalInternetFee,
        'totalCableTVFee': totalCableTVFee,
        'totalHotWaterFee': totalHotWaterFee,
        'totalManagementFee': totalManagementFee,
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
  // UTILITY - Get utility usage statistics
  // ========================================
  Future<Map<String, dynamic>> getUtilityUsageStats(
    String roomId,
    DateTime startDate,
    DateTime endDate,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('payments')
          .where('roomId', isEqualTo: roomId)
          .get();

      final payments = snapshot.docs
          .map((doc) => Payment.fromMap(doc.id, doc.data()))
          .where((p) => 
              p.createdAt.isAfter(startDate) && 
              p.createdAt.isBefore(endDate))
          .toList();

      final electricityPayments = payments.where((p) => p.type == PaymentType.electricity).toList();
      final waterPayments = payments.where((p) => p.type == PaymentType.water).toList();

      final totalElectricityUsage = electricityPayments
          .fold<double>(0.0, (sum, p) => sum + (p.electricityUsage ?? 0));
      
      final totalWaterUsage = waterPayments
          .fold<double>(0.0, (sum, p) => sum + (p.waterUsage ?? 0));

      final avgElectricityUsage = electricityPayments.isNotEmpty
          ? totalElectricityUsage / electricityPayments.length
          : 0.0;
      
      final avgWaterUsage = waterPayments.isNotEmpty
          ? totalWaterUsage / waterPayments.length
          : 0.0;

      return {
        'totalElectricityUsage': totalElectricityUsage,
        'totalWaterUsage': totalWaterUsage,
        'avgElectricityUsage': avgElectricityUsage,
        'avgWaterUsage': avgWaterUsage,
        'electricityPaymentsCount': electricityPayments.length,
        'waterPaymentsCount': waterPayments.length,
      };
    } catch (e) {
      print('Error getting utility usage stats: $e');
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
          description: 'Tiền thuê từ ${_formatDate(billingStart)} đến ${_formatDate(billingEnd)}',
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

  // ========================================
  // HELPER - Format date
  // ========================================
  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }
}