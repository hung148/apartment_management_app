const ACTIVE = new Set(['pending', 'confirmed', 'checkedIn']);
const STATUSES = new Set([...ACTIVE, 'checkedOut', 'cancelled', 'noShow']);
const METHODS = new Set(['cash', 'bankTransfer', 'momo', 'zalopay', 'creditCard', 'other']);
const EDITABLE = ['guestName', 'guestPhone', 'guestIdNumber', 'numberOfGuests', 'startTime', 'endTime', 'totalPrice', 'depositAmount', 'notes', 'pricingType', 'source'];
const cents = value => Math.round(Number(value || 0) * 100);
const ms = value => value && typeof value.toMillis === 'function' ? value.toMillis() : value;
const overlaps = (start, end, otherStart, otherEnd) => start < otherEnd && end > otherStart;

function createCalendarHandler({db, Timestamp, FieldValue, HttpsError}) {
  const fail = (code, key) => { throw new HttpsError(code, key); };
  const id = value => typeof value === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(value);
  const amount = value => typeof value === 'number' && Number.isFinite(value) && value >= 0 && value <= 1e12;
  const decode = value => {
    if (value && typeof value === 'object' && !Array.isArray(value)) {
      if (Object.keys(value).length === 1 && Number.isFinite(value.__timestamp)) return Timestamp.fromMillis(value.__timestamp);
      return Object.fromEntries(Object.entries(value).map(([k,v]) => [k,decode(v)]));
    }
    return Array.isArray(value) ? value.map(decode) : value;
  };
  return async (input, context) => {
    if (!context.auth) fail('unauthenticated', 'booking_sign_in_required');
    const {action, bookingId, operationId} = input || {};
    if (!id(bookingId)) fail('invalid-argument', 'booking_invalid_request');
    const proposed = decode(input.booking || input.changes || {});
    const ref = db.collection('bookings').doc(bookingId);
    return db.runTransaction(async tx => {
      const existing = await tx.get(ref);
      const old = existing.exists ? existing.data() : null;
      if (action !== 'create' && !old) fail('not-found', 'booking_not_found');
      const orgId = old?.organizationId || proposed.organizationId;
      const roomId = old?.roomId || proposed.roomId;
      if (!id(orgId) || !id(roomId)) fail('invalid-argument', 'booking_invalid_request');
      const org = await tx.get(db.collection('organizations').doc(orgId));
      const membership = await tx.get(db.collection('memberships').doc(`${context.auth.uid}_${orgId}`));
      if (!org.exists || (org.data().createdBy !== context.auth.uid &&
          (!membership.exists || membership.data().organizationId !== orgId ||
            membership.data().ownerId !== context.auth.uid || membership.data().status !== 'active' ||
            !['admin','member'].includes(membership.data().role)))) fail('permission-denied', 'booking_access_denied');
      const roomRef = db.collection('rooms').doc(roomId);
      const roomDoc = await tx.get(roomRef);
      if (!roomDoc.exists || roomDoc.data().organizationId !== orgId) fail('not-found', 'booking_room_not_found');
      const room = roomDoc.data();
      const validMoney=value => amount(value) && Math.abs(value*((old?.currency || room.currency) === 'USD' ? 100 : 1)-Math.round(value*((old?.currency || room.currency) === 'USD' ? 100 : 1))) < 0.00001;
      // Every booking mutation reads AND writes this shared document. Concurrent
      // requests for the same room therefore serialize, even with zero bookings.
      if (action === 'create' && old) {
        if (proposed.roomId !== old.roomId || proposed.organizationId !== old.organizationId || old.createdBy !== context.auth.uid) fail('already-exists','booking_invalid_request');
        return {id: bookingId};
      }
      let next = old ? {...old} : {
        organizationId: orgId, roomId, buildingId: room.buildingId,
        currency: room.currency || 'VND', status: 'pending', paidAmount: 0,
        depositPaidAmount: 0, depositRefundedAmount: 0, depositRefunded: false,
        createdAt: Timestamp.now(), createdBy: context.auth.uid,
      };
      const now = Timestamp.now();
      let paymentRef, payment;
      if (action === 'create' || action === 'edit') {
        if (old && !ACTIVE.has(old.status)) fail('failed-precondition','booking_invalid_transition');
        for (const key of EDITABLE) if (key in proposed) next[key] = proposed[key];
        next.pricingType ||= 'hourly'; next.source ||= 'walkIn';
        if (typeof next.guestName !== 'string' || !next.guestName.trim() || next.guestName.length > 100 ||
            (next.guestPhone != null && (typeof next.guestPhone !== 'string' || next.guestPhone.length > 30)) ||
            (next.notes != null && (typeof next.notes !== 'string' || next.notes.length > 2000)) ||
            !['hourly','daily','overnight'].includes(next.pricingType) ||
            !['walkIn','phone','app','online','other'].includes(next.source) ||
            !validMoney(next.totalPrice) || cents(next.totalPrice) < cents(next.paidAmount) ||
            (next.depositAmount != null && (!validMoney(next.depositAmount) || cents(next.depositAmount) < cents(next.depositPaidAmount)))) fail('invalid-argument', 'booking_invalid_request');
        if (!['hourly','both'].includes(room.rentalMode)) fail('failed-precondition','booking_room_not_hourly');
        const start = ms(next.startTime), end = ms(next.endTime);
        if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start ||
            end - start < (room.minBookingHours || 0) * 3600000) fail('invalid-argument','booking_invalid_dates');
        const bookings = await tx.get(db.collection('bookings').where('roomId','==',roomId));
        const tenants = await tx.get(db.collection('tenants').where('roomId','==',roomId));
        const buffer = Math.max(0, room.cleaningBufferMinutes || 0) * 60000;
        for (const doc of bookings.docs) {
          const b = doc.data();
          if (doc.id !== bookingId && ACTIVE.has(b.status) && overlaps(start-buffer,end+buffer,ms(b.startTime),ms(b.endTime))) fail('already-exists','booking_conflict');
        }
        for (const doc of tenants.docs) {
          const t = doc.data();
          if (t.status === 'active' && overlaps(start,end,ms(t.moveInDate),t.moveOutDate ? ms(t.moveOutDate) : Infinity)) fail('already-exists','booking_conflict');
        }
        next.startTime = Timestamp.fromMillis(start); next.endTime = Timestamp.fromMillis(end);
      } else if (action === 'status') {
        const status = input.status;
        const transitions = {pending:['confirmed','checkedIn','cancelled','noShow'], confirmed:['checkedIn','cancelled','noShow'], checkedIn:['cancelled']};
        if (!STATUSES.has(status) || !(transitions[old.status] || []).includes(status)) fail('failed-precondition','booking_invalid_transition');
        next.status = status;
        if (status === 'checkedIn') { next.checkedInAt = now; next.checkedInBy = context.auth.uid; }
        if (status === 'cancelled') next.cancelReason = String(input.reason || '').slice(0,1000);
      } else if (['payment','deposit','refund','checkout'].includes(action)) {
        if (action === 'checkout' && old.status === 'checkedOut') return {id: bookingId, paymentId: old.paymentId || null};
        if (!id(operationId) && action !== 'checkout') fail('invalid-argument','booking_invalid_request');
        paymentRef = db.collection('payments').doc(`booking_${bookingId}_${action === 'checkout' ? 'checkout' : operationId}`);
        const prior = await tx.get(paymentRef);
        if (prior.exists) return {id:bookingId,paymentId:paymentRef.id};
        if (action === 'checkout' ? old.status !== 'checkedIn' : action !== 'refund' && !ACTIVE.has(old.status)) fail('failed-precondition','booking_invalid_transition');
        if (!METHODS.has(input.paymentMethod)) fail('invalid-argument','booking_invalid_request');
        const value = action === 'checkout' ? (cents(old.totalPrice)-cents(old.paidAmount))/100 : input.amount;
        if (!validMoney(value) || (action !== 'checkout' && value <= 0)) fail('invalid-argument','booking_invalid_amount');
        if ((action === 'payment' || action === 'checkout') && cents(value)+cents(old.paidAmount) > cents(old.totalPrice)) fail('invalid-argument','booking_overpayment');
        if (action === 'deposit' && cents(value)+cents(old.depositPaidAmount) > cents(old.depositAmount)) fail('invalid-argument','booking_overpayment');
        if (action === 'refund' && cents(value) > cents(old.depositPaidAmount)-cents(old.depositRefundedAmount)) fail('invalid-argument','booking_refund_exceeds_deposit');
        if (action === 'deposit') next.depositPaidAmount = (cents(old.depositPaidAmount)+cents(value))/100;
        else if (action === 'refund') {
          next.depositRefundedAmount = (cents(old.depositRefundedAmount)+cents(value))/100;
          next.depositRefunded = cents(next.depositRefundedAmount) === cents(old.depositPaidAmount);
        } else next.paidAmount = (cents(old.paidAmount)+cents(value))/100;
        payment = {organizationId:orgId, buildingId:room.buildingId, roomId, tenantId:null,
          tenantName:old.guestName, bookingId, type:['deposit','refund'].includes(action) ? 'deposit' : 'hourlyRent',
          status:action === 'refund' ? 'refunded' : 'paid', amount:value,
          paidAmount:action === 'refund' ? 0 : value, currency:old.currency || 'VND',
          paymentMethod:input.paymentMethod, dueDate:old.endTime, paidAt:now, createdAt:now,
          billingStartDate:old.startTime, billingEndDate:old.endTime,
          descriptionKey:action === 'refund' ? 'booking_deposit_refund' : 'booking_payment',
        };
        if (action === 'checkout') {next.status='checkedOut';next.checkedOutAt=now;next.checkedOutBy=context.auth.uid;next.paymentId=value > 0 ? paymentRef.id : old.paymentId || null;}
        if (value === 0) payment = null;
      } else if (action === 'delete') {
        if (ACTIVE.has(old.status) || cents(old.paidAmount) || cents(old.depositPaidAmount)) fail('failed-precondition','booking_delete_has_payments');
      } else fail('invalid-argument','booking_invalid_request');
      tx.update(roomRef,{bookingRevision:FieldValue.increment(1)});
      if (action === 'delete') tx.delete(ref);
      else tx.set(ref,{...next,updatedAt:now});
      if (payment) tx.create(paymentRef,payment);
      return {id:bookingId, ...(payment ? {paymentId:paymentRef.id} : {})};
    });
  };
}
module.exports = {createCalendarHandler, overlaps, cents};
// Tenant moves and active leases use the same room lock as reservations.
function createTenantHandler({db, Timestamp, FieldValue, HttpsError}) {
  const fail=(code,key) => {throw new HttpsError(code,key);};
  const decode=value => {
    if (value && typeof value === 'object' && !Array.isArray(value)) {
      if (Object.keys(value).length === 1 && Number.isFinite(value.__timestamp)) return Timestamp.fromMillis(value.__timestamp);
      return Object.fromEntries(Object.entries(value).map(([k,v]) => [k,decode(v)]));
    }
    return Array.isArray(value) ? value.map(decode) : value;
  };
  return async (input,context) => {
    if (!context.auth) fail('unauthenticated','booking_sign_in_required');
    if (!/^[A-Za-z0-9_-]{1,128}$/.test(input.tenantId || '')) fail('invalid-argument','booking_invalid_request');
    const ref=db.collection('tenants').doc(input.tenantId);
    return db.runTransaction(async tx => {
      const snapshot=await tx.get(ref), old=snapshot.exists ? snapshot.data() : null;
      if (input.create && old) {
        // A create retry must still authenticate below, then return the existing record.
      } else if (!input.create && !old) fail('not-found','booking_not_found');
      const patch=decode(input.tenant || {});
      const next={...(old || {}),...patch};
      if (old && patch.organizationId && old.organizationId !== patch.organizationId) fail('permission-denied','booking_access_denied');
      const orgId=old?.organizationId || next.organizationId;
      if (!/^[A-Za-z0-9_-]{1,128}$/.test(orgId || '') || !/^[A-Za-z0-9_-]{1,128}$/.test(next.roomId || '')) fail('invalid-argument','booking_invalid_request');
      const org=await tx.get(db.collection('organizations').doc(orgId));
      const member=await tx.get(db.collection('memberships').doc(`${context.auth.uid}_${orgId}`));
      if (!org.exists || (org.data().createdBy !== context.auth.uid && (!member.exists || member.data().organizationId !== orgId || member.data().ownerId !== context.auth.uid || member.data().role !== 'admin' || member.data().status !== 'active'))) fail('permission-denied','booking_access_denied');
      if (input.create && old) return {id:ref.id};
      const roomRef=db.collection('rooms').doc(next.roomId), room=await tx.get(roomRef);
      if (!room.exists || room.data().organizationId !== orgId) fail('not-found','booking_room_not_found');
      let previousRoom;
      if (old && old.roomId !== next.roomId) previousRoom=await tx.get(db.collection('rooms').doc(old.roomId));
      if (!['active','inactive','suspended','moveOut'].includes(next.status) || typeof next.fullName !== 'string' || !next.fullName.trim()) fail('invalid-argument','booking_invalid_request');
      const start=ms(next.moveInDate), end=next.moveOutDate ? ms(next.moveOutDate) : Infinity;
      if (!Number.isFinite(start) || end <= start) fail('invalid-argument','booking_invalid_dates');
      if (next.status === 'active') {
        const bookings=await tx.get(db.collection('bookings').where('roomId','==',next.roomId));
        for (const doc of bookings.docs) {
          const b=doc.data();
          if (ACTIVE.has(b.status) && overlaps(start,end,ms(b.startTime),ms(b.endTime))) fail('already-exists','booking_conflict');
        }
      }
      next.organizationId=orgId;next.buildingId=room.data().buildingId;
      next.currency=old?.currency || room.data().currency || 'VND';
      next.createdAt=old?.createdAt || Timestamp.now();next.updatedAt=Timestamp.now();
      next.createdBy=old?.createdBy || context.auth.uid;next.updatedBy=context.auth.uid;
      tx.update(roomRef,{bookingRevision:FieldValue.increment(1)});
      if (previousRoom?.exists) tx.update(previousRoom.ref,{bookingRevision:FieldValue.increment(1)});
      tx.set(ref,next);
      return {id:ref.id};
    });
  };
}
module.exports.createTenantHandler=createTenantHandler;
