'use strict';

const {createHash} = require('node:crypto');
const {allows} = require('./team_access');

// V2 only. Amounts in commands are integer minor units (VND dong, USD cents).
// Invoice creation/editing and booking payments have separate workflows.
function createPaymentHandler({db, Timestamp, HttpsError}) {
  const fail = (code, message) => { throw new HttpsError(code, message); };
  const id = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(value);
  const hash = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
  return async request => {
    const uid = request.auth?.uid;
    if (!uid) fail('unauthenticated', 'payment_sign_in_required');
    const input = request.data;
    const collect = input?.action === 'collect';
    const fields = ['organizationId','paymentId','operationId','action','amountMinor', collect ? 'paymentMethod' : 'reason'];
    if (!input || !['collect','refund'].includes(input.action) ||
        Object.keys(input).some(key => !fields.includes(key)) ||
        !id(input.organizationId) || !id(input.paymentId) || !id(input.operationId) ||
        !Number.isSafeInteger(input.amountMinor) || input.amountMinor <= 0 ||
        (collect && !['cash','bankTransfer','momo','zalopay','creditCard','other'].includes(input.paymentMethod)) ||
        (!collect && (typeof input.reason !== 'string' || !input.reason.trim() || input.reason.length > 500))) {
      fail('invalid-argument', 'payment_invalid_input');
    }
    const {organizationId, paymentId, operationId} = input;
    const key = hash(['standalone-payment', organizationId, uid, operationId]);
    const fingerprint = hash(fields.map(field => input[field]));
    const paymentRef = db.collection('payments').doc(paymentId);
    const operationRef = db.collection('paymentOperations').doc(key);
    return db.runTransaction(async tx => {
      const org = await tx.get(db.collection('organizations').doc(organizationId));
      if (!org.exists || org.data().accessVersion !== 2) fail('failed-precondition', 'team_migration_required');
      const membership = await tx.get(db.collection('memberships').doc(`${uid}_${organizationId}`));
      const actor = membership.exists ? membership.data() : null;
      const permission = collect ? 'collectPayments' : 'refundPayments';
      const context = {organizationId, userId: uid};
      if (!allows(actor, permission, context)) fail('permission-denied', 'payment_access_denied');
      const snapshot = await tx.get(paymentRef);
      if (!snapshot.exists || snapshot.data().organizationId !== organizationId) fail('not-found', 'payment_not_found');
      const payment = snapshot.data();
      if (!id(payment.buildingId) || !allows(actor, permission, {...context, buildingId: payment.buildingId})) {
        fail('permission-denied', 'payment_access_denied');
      }
      const building = await tx.get(db.collection('buildings').doc(payment.buildingId));
      if (!building.exists || building.data().organizationId !== organizationId) fail('failed-precondition', 'payment_invalid_property');
      // Recheck current authorization even on a previously successful operation.
      const prior = await tx.get(operationRef);
      if (prior.exists) {
        if (prior.data().fingerprint !== fingerprint) fail('already-exists', 'payment_operation_reused');
        return prior.data().result;
      }
      if (payment.direction === 'expense') fail('failed-precondition','payment_use_expense_workflow');
      if (paymentId.startsWith('booking_') || payment.bookingId != null || payment.type === 'hourlyRent') {
        fail('failed-precondition', 'payment_use_booking_workflow');
      }
      if (!['pending','partial','overdue','paid','refunded'].includes(payment.status)) fail('failed-precondition', 'payment_invalid_status');
      const scale = {VND: 1, USD: 100}[payment.currency];
      if (!scale) fail('failed-precondition', 'payment_unsupported_currency');
      const minor = value => {
        const scaled = value * scale;
        const rounded = Math.round(scaled);
        if (typeof value !== 'number' || !Number.isFinite(value) || value < 0 ||
            !Number.isSafeInteger(rounded) || Math.abs(scaled - rounded) > 1e-7) {
          fail('failed-precondition', 'payment_invalid_stored_amount');
        }
        return rounded;
      };
      const totalMinor = ['amount','internetFee','cableTVFee','hotWaterFee','lateFee','taxAmount']
        .reduce((sum, field) => sum + minor(field === 'amount' ? payment[field] : (payment[field] ?? 0)), 0);
      const previousMinor = minor(payment.paidAmount);
      if (!Number.isSafeInteger(totalMinor) || totalMinor <= 0 || previousMinor > totalMinor) fail('failed-precondition', 'payment_invalid_stored_amount');
      if (input.amountMinor > (collect ? totalMinor - previousMinor : previousMinor)) fail('failed-precondition', 'payment_amount_exceeds_balance');
      const paidMinor = previousMinor + (collect ? input.amountMinor : -input.amountMinor);
      const status = paidMinor === totalMinor ? 'paid' : paidMinor === 0 ? 'refunded' : 'partial';
      const now = Timestamp.now();
      const patch = {paidAmount: paidMinor / scale, status, updatedAt: now, updatedBy: uid};
      if (collect) Object.assign(patch, {paidAt: now, paidBy: uid, paymentMethod: input.paymentMethod});
      else Object.assign(patch, {lastRefundedAt: now, lastRefundedBy: uid});
      const result = {paymentId, operationId, status, paidMinor, totalMinor, currency: payment.currency, recordedAt: now.toDate().toISOString()};
      const summary = (paidAmount, status) => ({buildingId: payment.buildingId, currency: payment.currency, paidAmount, status});
      tx.update(paymentRef, patch);
      if(payment.invoiceVersion===2)tx.create(paymentRef.collection('invoiceHistory').doc(key),{organizationId,actorId:uid,createdAt:now,action:input.action,reason:collect?input.paymentMethod:input.reason.trim(),before:{totalMinor,paidAmount:payment.paidAmount,status:payment.status},after:{totalMinor,paidAmount:patch.paidAmount,status:patch.status}});
      tx.create(operationRef, {organizationId, paymentId, actorId: uid, action: input.action,
        amountMinor: input.amountMinor, currency: payment.currency, fingerprint, createdAt: now, result,
        ...(collect ? {paymentMethod: input.paymentMethod} : {reason: input.reason.trim()})});
      tx.create(db.collection('teamActivity').doc(key), {organizationId, actorId: uid,
        action: collect ? 'paymentCollect' : 'paymentRefund', targetId: paymentId, createdAt: now,
        before: summary(payment.paidAmount, payment.status), after: summary(patch.paidAmount, status)});
      return result;
    });
  };
}

module.exports = {createPaymentHandler};
