const {readReferenceRates,convertMinor}=require('./reference_rates');
const {bookingPrice}=require('./booking_quote');
const {createHash}=require('node:crypto');
const ACTIVE = new Set(['pending', 'confirmed', 'checkedIn']);
const {allows} = require('./team_access');
const {withinHours}=require('./booking_settings');
const {roomBlocked}=require('./technical_problems');
const STATUSES = new Set([...ACTIVE, 'checkedOut', 'cancelled', 'noShow']);
const METHODS = new Set(['cash', 'bankTransfer', 'momo', 'zalopay', 'creditCard', 'other']);
const EDITABLE = ['guestName', 'guestPhone', 'guestIdNumber', 'numberOfGuests', 'startTime', 'endTime', 'totalPrice', 'depositAmount', 'notes', 'pricingType', 'source',
  'guests', 'staffInChargeId', 'platform', 'contactChannel', 'depositNote', 'surcharges', 'nightPrices', 'hourlyPrice'];
const PRICING = ['hourly', 'daily', 'overnight', 'nightly'];
// B2 booking details. Older bookings simply lack these fields.
const PLATFORMS = new Set(['direct', 'airbnb', 'booking', 'agoda', 'traveloka', 'other']);
const CHANNELS = new Set(['phone', 'zalo', 'whatsapp', 'messenger', 'other']);
const shortText = (v, max) => typeof v === 'string' && v.length <= max;
const plainObject = v => !!v && typeof v === 'object' && !Array.isArray(v);
function validExtras(b, validMoney) {
  if (b.guests != null && (!Array.isArray(b.guests) || b.guests.length > 20 ||
      new Set(b.guests.map(g => g?.id)).size !== b.guests.length ||
      b.guests.some(g => !plainObject(g) || Object.keys(g).some(k => !['id','name','idNumber'].includes(k)) ||
        !(typeof g.id === 'string' && /^[A-Za-z0-9_-]{1,40}$/.test(g.id)) || !shortText(g.name, 100) || !g.name.trim() ||
        (g.idNumber != null && !shortText(g.idNumber, 30))))) return false;
  if (b.guestIdNumber != null && !shortText(b.guestIdNumber, 30)) return false;
  if (b.numberOfGuests != null && (!Number.isSafeInteger(b.numberOfGuests) || b.numberOfGuests < 1 || b.numberOfGuests > 100)) return false;
  if (b.staffInChargeId != null && !(typeof b.staffInChargeId === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(b.staffInChargeId))) return false;
  if (b.platform != null && !PLATFORMS.has(b.platform)) return false;
  if (b.contactChannel != null && !CHANNELS.has(b.contactChannel)) return false;
  if (b.depositNote != null && !shortText(b.depositNote, 500)) return false;
  if (b.surcharges != null && (!Array.isArray(b.surcharges) || b.surcharges.length > 20 ||
      b.surcharges.some(s => !plainObject(s) || Object.keys(s).some(k => !['label','amount','basis','unitAmount','count'].includes(k)) ||
        !shortText(s.label, 80) || !s.label.trim() || !validMoney(s.amount) || s.amount <= 0 ||
        // Per person (2026-10-04): price × guests = the line's amount.
        (s.basis != null && s.basis !== 'room' && s.basis !== 'person') ||
        (s.basis === 'person' && (!validMoney(s.unitAmount) || s.unitAmount <= 0 || !Number.isSafeInteger(s.count) || s.count < 1 || s.count > 100 ||
          Math.round(s.unitAmount * 100) * s.count !== Math.round(s.amount * 100)))))) return false;
  if (b.nightPrices != null && (!Array.isArray(b.nightPrices) || b.nightPrices.length > 366 || b.nightPrices.some(v => !validMoney(v) || v <= 0))) return false;
  if (b.hourlyPrice != null && (!validMoney(b.hourlyPrice) || b.hourlyPrice <= 0)) return false;
  return true;
}
const cents = value => Math.round(Number(value || 0) * 100);
const ms = value => value && typeof value.toMillis === 'function' ? value.toMillis() : value;
const overlaps = (start, end, otherStart, otherEnd) => start < otherEnd && end > otherStart;
// Audit snapshots deliberately omit guest identity, contact details and notes.
const AUDIT_FIELDS=['roomId','buildingId','status','startTime','endTime','moveInDate','moveOutDate','currency','totalPrice','paidAmount','depositPaidAmount','depositRefundedAmount'];
const auditSnapshot=value=>value?Object.fromEntries(AUDIT_FIELDS.filter(k=>value[k]!==undefined).map(k=>[k,value[k]])):null;
const comparable=value=>JSON.stringify(value,(_k,v)=>v&&typeof v.toMillis==='function'?v.toMillis():v);
function auditOperation(db,tx,{organizationId,actorId,action,targetId,old,next,createdAt}) {
  const changed=Object.keys(next).filter(k=>!['createdAt','updatedAt','createdBy','updatedBy'].includes(k)&&comparable(old?.[k])!==comparable(next[k]));
  if(old&&!changed.length)return;
  tx.create(db.collection('teamActivity').doc(),{organizationId,actorId,action,targetId,createdAt,
    before:auditSnapshot(old),after:{...auditSnapshot(next),changedFields:changed.filter(k=>AUDIT_FIELDS.includes(k))}});
}

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
    // context.serverQuote is set only by the bookings workspace callable, after it priced the booking
    // (rates, nights, custom night prices it authorised, surcharges). The public callable cannot set it.
    const serverQuote = context.serverQuote ?? null;
    const serverPriced = input.serverPricing === true || serverQuote !== null;
    // Surcharge lines and night prices must match the total, so only a server quote may write them.
    if (!serverQuote && ('surcharges' in proposed || 'nightPrices' in proposed || 'hourlyPrice' in proposed)) fail('invalid-argument', 'booking_invalid_request');
    // A deposit paid when the booking is made (2026-10-04) comes only from the bookings workspace, which checked it.
    const depositPayment = input.depositPayment == null ? null : decode(input.depositPayment);
    if (depositPayment && (!serverQuote || !['create','edit'].includes(action))) fail('invalid-argument', 'booking_invalid_request');
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
      const v2 = org.exists && org.data().accessVersion === 2;
      if (!org.exists || (!v2 && (org.data().createdBy !== context.auth.uid &&
          (!membership.exists || membership.data().organizationId !== orgId ||
            membership.data().ownerId !== context.auth.uid || membership.data().status !== 'active' ||
            !['admin','member'].includes(membership.data().role))))) fail('permission-denied', 'booking_access_denied');
      const roomRef = db.collection('rooms').doc(roomId);
      const roomDoc = await tx.get(roomRef);
      if (!roomDoc.exists || roomDoc.data().organizationId !== orgId) fail('not-found', 'booking_room_not_found');
      const room = roomDoc.data();
      if (v2) {
        const scope = {organizationId:orgId,userId:context.auth.uid,buildingId:room.buildingId};
        const actor = membership.exists ? membership.data() : null;
        const permission = ['refund','refundRent'].includes(action) ? 'refundPayments' :
          ['payment','deposit'].includes(action) ? 'collectPayments' : action === 'create' ? 'createBookings' : 'manageBookings';
        // "Own records only" grants: the booking must be one the member created or is in charge of.
        const bookingScope = old ? {...scope, record: old} : scope;
        if (!allows(actor,permission,permission === 'manageBookings' ? bookingScope : scope) ||
            (old && action !== 'create' && !allows(actor,'readBookings',bookingScope)) ||
            (action === 'checkout' && !allows(actor,'collectPayments',scope)) ||
            (depositPayment && !allows(actor,'collectPayments',scope)) ||
            (action === 'edit' && !serverPriced && old && proposed.totalPrice !== undefined && proposed.totalPrice !== old.totalPrice && !allows(actor,'overridePrices',scope)) ||
            action === 'delete') fail('permission-denied','booking_access_denied');
        // Creating an arbitrary custom-priced booking also requires price authority
        // until server-side rate calculation is integrated for receptionists.
        if (action === 'create' && !serverPriced && !allows(actor,'overridePrices',scope)) fail('permission-denied','booking_price_authority_required');
      }
      let commandRef,commandFingerprint;
      if(v2&&id(operationId)){
        const commandKey=createHash('sha256').update(JSON.stringify(['booking',orgId,context.auth.uid,operationId])).digest('hex');commandRef=db.doc(`bookingOperations/${commandKey}`);commandFingerprint=createHash('sha256').update(JSON.stringify(Object.fromEntries(Object.entries(input).filter(([key])=>key!=='propertyRevision').map(([key,value])=>key==='depositPayment'&&value?[key,{...value,paidAt:undefined}]:[key,value])))).digest('hex');// a deposit paid today is timed when the save arrives, so a retry has another time
        const prior=await tx.get(commandRef);if(prior.exists){if(context.workspaceFingerprint?prior.data().workspaceFingerprint!==context.workspaceFingerprint:prior.data().fingerprint!==commandFingerprint)fail('failed-precondition','booking_operation_reused');return prior.data().result;}
      }
      if(v2&&input.propertyRevision){const property=await tx.get(db.doc(`buildings/${room.buildingId}`));if(!property.exists||property.data().organizationId!==orgId||input.propertyRevision!==`${property.updateTime.seconds}:${property.updateTime.nanoseconds}`)fail('aborted','booking_property_changed');}
      if(v2&&input.revision&&(!existing.exists||input.revision!==`${existing.updateTime.seconds}:${existing.updateTime.nanoseconds}`))fail('aborted','booking_changed');
      if(v2&&input.roomRevision&&input.roomRevision!==`${roomDoc.updateTime.seconds}:${roomDoc.updateTime.nanoseconds}`)fail('aborted','booking_room_changed');
      if(v2&&serverQuote&&['create','edit'].includes(action)){proposed.totalPrice=serverQuote.total;proposed.pricingType=serverQuote.pricingType;}
      else if(v2&&input.serverPricing===true&&['create','edit'].includes(action)){
        try{const quote=bookingPrice(room,ms(proposed.startTime??old?.startTime),ms(proposed.endTime??old?.endTime),proposed.pricingType??old?.pricingType);proposed.totalPrice=quote.totalMinor/(quote.currency==='USD'?100:1);proposed.pricingType=quote.pricingType;}catch(e){fail('failed-precondition',e.message);}
      }
      const bookingCurrency=old?.currency||serverQuote?.currency||room.currency||'VND';
      if(v2&&action==='create'&&bookingCurrency!==(org.data().displayCurrency??room.currency??'VND'))fail('failed-precondition','booking_currency_changed');
      const validMoney=value => amount(value) && Math.abs(value*(bookingCurrency === 'USD' ? 100 : 1)-Math.round(value*(bookingCurrency === 'USD' ? 100 : 1))) < 0.00001;
      // Every booking mutation reads AND writes this shared document. Concurrent
      // requests for the same room therefore serialize, even with zero bookings.
      if (action === 'create' && old) {
        if (proposed.roomId !== old.roomId || proposed.organizationId !== old.organizationId || old.createdBy !== context.auth.uid) fail('already-exists','booking_invalid_request');
        return {id: bookingId};
      }
      let next = old ? {...old} : {
        organizationId: orgId, roomId, buildingId: room.buildingId,
        currency: bookingCurrency, ...(serverQuote?.sourceRates?{sourceRates:serverQuote.sourceRates}:{}), status: 'pending', paidAmount: 0,
        depositPaidAmount: 0, depositRefundedAmount: 0, depositRefunded: false,
        createdAt: Timestamp.now(), createdBy: context.auth.uid,
      };
      const now = Timestamp.now();
      let paymentRef, payment, originalInput;
      if (action === 'create' || action === 'edit') {
        if (old && !ACTIVE.has(old.status)) fail('failed-precondition','booking_invalid_transition');
        for (const key of EDITABLE) if (key in proposed) next[key] = proposed[key];
        next.pricingType ||= 'hourly'; next.source ||= 'walkIn';
        if (typeof next.guestName !== 'string' || !next.guestName.trim() || next.guestName.length > 100 ||
            (next.guestPhone != null && (typeof next.guestPhone !== 'string' || next.guestPhone.length > 30)) ||
            (next.notes != null && (typeof next.notes !== 'string' || next.notes.length > 2000)) ||
            !PRICING.includes(next.pricingType) ||
            !['walkIn','phone','app','online','other'].includes(next.source) || !validExtras(next, validMoney) ||
            !validMoney(next.totalPrice) || cents(next.totalPrice) < cents(next.paidAmount) ||
            (next.depositAmount != null && (!validMoney(next.depositAmount) || cents(next.depositAmount) < cents(next.depositPaidAmount)))) fail('invalid-argument', 'booking_invalid_request');
        if (next.staffInChargeId != null && next.staffInChargeId !== old?.staffInChargeId) {
          const staff = await tx.get(db.collection('staffProfiles').doc(next.staffInChargeId));
          if (!staff.exists || staff.data().organizationId !== orgId || staff.data().employmentStatus === 'inactive') fail('invalid-argument','booking_staff_invalid');
        }
        const start = ms(next.startTime), end = ms(next.endTime);
        if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start ||
            end - start < (room.minBookingHours || 0) * 3600000) fail('invalid-argument','booking_invalid_dates');
        // B7: an open technical problem marked "room unavailable" stops new or moved bookings.
        if (v2 && roomBlocked(room) && (!old || ms(old.startTime) !== start || ms(old.endTime) !== end)) fail('failed-precondition','room_has_open_problem');
        if(v2&&(room.operatingSchedule!=null||room.operatingHoursStartMin!=null||room.operatingHoursEndMin!=null)){
          const property=await tx.get(db.doc(`buildings/${room.buildingId}`));
          if(!property.exists||property.data().organizationId!==orgId||!withinHours(start,end,room,property.data().timeZone))fail('failed-precondition','booking_outside_operating_hours');
        }
        const bookings = await tx.get(db.collection('bookings').where('roomId','==',roomId));
        const tenants = await tx.get(db.collection('tenants').where('roomId','==',roomId));
        const buffer = Math.max(0, room.cleaningBufferMinutes || 0) * 60000;
        for (const doc of bookings.docs) {
          const b = doc.data();
          if (doc.id !== bookingId && ACTIVE.has(b.status) && overlaps(start-buffer,end+buffer,ms(b.startTime),ms(b.endTime))) fail('already-exists','booking_conflict');
        }
        for (const doc of tenants.docs) {
          const t = doc.data();
          if ((['active','suspended'].includes(t.status)||t.moveOutDate) && overlaps(start,end,ms(t.occupancyStartDate??t.moveInDate),t.moveOutDate ? ms(t.moveOutDate) : Infinity)) fail('already-exists','booking_conflict');
        }
        const history=await tx.get(db.collection('leaseOccupancy').where('roomId','==',roomId));
        if(history.docs.some(doc=>overlaps(start,end,ms(doc.data().start),ms(doc.data().end))))fail('already-exists','booking_conflict');
        next.startTime = Timestamp.fromMillis(start); next.endTime = Timestamp.fromMillis(end);
        // The deposit is part of the total: it is recorded as a payment, dated the day it was paid.
        if (depositPayment) {
          const dp = depositPayment;
          if(dp.originalInput && dp.originalInput.currency !== (org.data().displayCurrency??bookingCurrency)) fail('failed-precondition','booking_currency_changed');
          if (!v2 || !id(operationId) || !plainObject(dp) || Object.keys(dp).some(k => !['amount','paymentMethod','paidOn','paidAt','originalInput'].includes(k)) ||
              !validMoney(dp.amount) || dp.amount <= 0 || !['cash','bankTransfer','creditCard'].includes(dp.paymentMethod) ||
              typeof dp.paidOn !== 'string' || typeof dp.paidAt?.toMillis !== 'function') fail('invalid-argument','booking_invalid_request');
          if (plainObject(old?.depositPayment)) fail('failed-precondition','booking_deposit_recorded');
          if (cents(next.paidAmount)+cents(dp.amount) > cents(next.totalPrice)) fail('invalid-argument','booking_overpayment');
          paymentRef = db.collection('payments').doc(`booking_${bookingId}_${operationId}`);
          next.paidAmount = (cents(next.paidAmount)+cents(dp.amount))/100;
          next.depositPayment = {...(dp.originalInput?{originalInput:dp.originalInput}:{}),amount:dp.amount, paymentMethod:dp.paymentMethod, paidOn:dp.paidOn, paidAt:dp.paidAt, paymentId:paymentRef.id};
          payment = {...(dp.originalInput?{originalInput:dp.originalInput}:{}),organizationId:orgId, buildingId:room.buildingId, roomId, tenantId:null,
            tenantName:next.guestName, bookingId, type:'hourlyRent', status:'paid', amount:dp.amount,
            paidAmount:dp.amount, currency:next.currency || 'VND', paymentMethod:dp.paymentMethod,
            dueDate:next.endTime, paidAt:dp.paidAt, createdAt:now, billingStartDate:next.startTime, billingEndDate:next.endTime,
            descriptionKey:'booking_deposit_payment', bookingDeposit:true,
          };
        }
      } else if (action === 'status') {
        const status = input.status;
        const transitions = {pending:['confirmed','checkedIn','cancelled','noShow'], confirmed:['checkedIn','cancelled','noShow'], checkedIn:['cancelled']};
        if (!STATUSES.has(status) || !(transitions[old.status] || []).includes(status)) fail('failed-precondition','booking_invalid_transition');
        next.status = status;
        if (status === 'checkedIn') { next.checkedInAt = now; next.checkedInBy = context.auth.uid; }
        if (status === 'cancelled') next.cancelReason = String(input.reason || '').slice(0,1000);
      } else if (['payment','deposit','refund','refundRent','checkout'].includes(action)) {
        if (action === 'checkout' && old.status === 'checkedOut') return {id: bookingId, paymentId: old.paymentId || null};
        if (!id(operationId) && action !== 'checkout') fail('invalid-argument','booking_invalid_request');
        paymentRef = db.collection('payments').doc(`booking_${bookingId}_${action === 'checkout' ? 'checkout' : operationId}`);
        const prior = await tx.get(paymentRef);
        if (prior.exists) return {id:bookingId,paymentId:paymentRef.id};
        if (action === 'checkout' ? old.status !== 'checkedIn' : !['refund','refundRent'].includes(action) && !ACTIVE.has(old.status)) fail('failed-precondition','booking_invalid_transition');
        if (!METHODS.has(input.paymentMethod)) fail('invalid-argument','booking_invalid_request');
        // Receiving account (B8-lite): cash or one of the organization's accounts. The label is copied so
        // old payments keep it after the account is renamed or removed.
        let account = null;
        if (input.accountId != null) {
          if (input.accountId === 'cash') account = {id: 'cash', label: ''};
          else {
            const list = Array.isArray(org.data().paymentAccounts) ? org.data().paymentAccounts : [];
            const found = list.find(a => a && a.id === input.accountId);
            if (!found) fail('invalid-argument','booking_account_invalid');
            account = {id: found.id, label: found.label};
          }
        }
        const value = action === 'checkout' ? (cents(old.totalPrice)-cents(old.paidAmount))/100 : input.amount;
        if (!validMoney(value) || (action !== 'checkout' && value <= 0)) fail('invalid-argument','booking_invalid_amount');
        if(input.inputCurrency!==undefined||input.inputAmountMinor!==undefined||input.ratesId!==undefined){
          if(action==='checkout'||!['USD','VND'].includes(input.inputCurrency)||!Number.isSafeInteger(input.inputAmountMinor)||input.inputAmountMinor<=0||input.inputAmountMinor>1e12)fail('invalid-argument','booking_invalid_amount');
          if(input.inputCurrency!==(org.data().displayCurrency??bookingCurrency))fail('failed-precondition','booking_currency_changed');
          let converted=input.inputAmountMinor,rates=null;
          if(input.inputCurrency!==bookingCurrency){
            try{rates=await readReferenceRates(tx,db,input.ratesId);converted=convertMinor(input.inputAmountMinor,input.inputCurrency,bookingCurrency,rates);}
            catch(e){fail('failed-precondition',e.message);}
          }
          const sourceMinor=Math.round(value*(bookingCurrency==='USD'?100:1));
          const balance=action==='payment'?old.totalPrice-old.paidAmount:action==='deposit'?old.depositAmount-old.depositPaidAmount:action==='refund'?old.depositPaidAmount-old.depositRefundedAmount:old.paidAmount;
          const balanceMinor=Math.round(balance*(bookingCurrency==='USD'?100:1));
          // Only the exact outstanding balance may preserve a source-unit
          // remainder hidden by display rounding. Arbitrary partial amounts may not.
          if(converted!==sourceMinor&&!(rates&&sourceMinor===balanceMinor&&convertMinor(balanceMinor,bookingCurrency,input.inputCurrency,rates)===input.inputAmountMinor))fail('invalid-argument','booking_invalid_conversion');
          originalInput={currency:input.inputCurrency,amountMinor:input.inputAmountMinor,...(input.ratesId?{exchangeRateSnapshotId:input.ratesId}:{}),...(converted!==sourceMinor?{roundingAdjustmentMinor:sourceMinor-converted}:{})};
        }
        if ((action === 'payment' || action === 'checkout') && cents(value)+cents(old.paidAmount) > cents(old.totalPrice)) fail('invalid-argument','booking_overpayment');
        if (action === 'deposit' && cents(value)+cents(old.depositPaidAmount) > cents(old.depositAmount)) fail('invalid-argument','booking_overpayment');
        if (action === 'refund' && cents(value) > cents(old.depositPaidAmount)-cents(old.depositRefundedAmount)) fail('invalid-argument','booking_refund_exceeds_deposit');
        if (action === 'refundRent' && cents(value)>cents(old.paidAmount))fail('invalid-argument','booking_refund_exceeds_payment');
        if (action === 'refundRent') next.paidAmount=(cents(old.paidAmount)-cents(value))/100;
        else if (action === 'deposit') next.depositPaidAmount = (cents(old.depositPaidAmount)+cents(value))/100;
        else if (action === 'refund') {
          next.depositRefundedAmount = (cents(old.depositRefundedAmount)+cents(value))/100;
          next.depositRefunded = cents(next.depositRefundedAmount) === cents(old.depositPaidAmount);
        } else next.paidAmount = (cents(old.paidAmount)+cents(value))/100;
        payment = {...(originalInput?{originalInput}:{}),organizationId:orgId, buildingId:room.buildingId, roomId, tenantId:null,
          tenantName:old.guestName, bookingId, type:['deposit','refund'].includes(action) ? 'deposit' : 'hourlyRent',
          status:['refund','refundRent'].includes(action) ? 'refunded' : 'paid', amount:value,
          paidAmount:['refund','refundRent'].includes(action) ? 0 : value, currency:old.currency || 'VND',
          paymentMethod:input.paymentMethod, ...(account ? {receivedAccountId:account.id, receivedAccountLabel:account.label} : {}), dueDate:old.endTime, paidAt:now, createdAt:now,
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
      if(v2) auditOperation(db,tx,{organizationId:orgId,actorId:context.auth.uid,action:`booking_${action}`,targetId:bookingId,old,next,createdAt:now});
      const result={id:bookingId, ...(payment ? {paymentId:paymentRef.id} : {})};
      if(commandRef)tx.create(commandRef,{organizationId:orgId,actorId:context.auth.uid,createdAt:now,fingerprint:commandFingerprint,...(originalInput?{originalInput}:{}),...(context.workspaceFingerprint?{workspaceFingerprint:context.workspaceFingerprint}:{}),result,...(input.priceOverrideReason?{priceOverrideReason:input.priceOverrideReason}:{}),...(input.reason?{reason:input.reason}:{})});
      return result;
    });
  };
}
module.exports = {createCalendarHandler, overlaps, cents};
// Tenant moves and active leases use the same room lock as reservations.
function createTenantHandler({db, Timestamp, FieldValue, HttpsError}) {
  const {leaseDatePolicy}=require('./lease_dates');
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
      const v2 = org.exists && org.data().accessVersion === 2;
      if (!org.exists || (!v2 && (org.data().createdBy !== context.auth.uid && (!member.exists || member.data().organizationId !== orgId || member.data().ownerId !== context.auth.uid || member.data().role !== 'admin' || member.data().status !== 'active')))) fail('permission-denied','booking_access_denied');
      const roomRef=db.collection('rooms').doc(next.roomId), room=await tx.get(roomRef);
      if (!room.exists || room.data().organizationId !== orgId) fail('not-found','booking_room_not_found');
      let previousRoom;
      if (old && old.roomId !== next.roomId) previousRoom=await tx.get(db.collection('rooms').doc(old.roomId));
      if (v2) {
        const actor=member.exists?member.data():null;
        const scope={organizationId:orgId,userId:context.auth.uid};
        if (!allows(actor,'manageLease',{...scope,buildingId:room.data().buildingId}) ||
            (old && !allows(actor,'manageLease',{...scope,buildingId:old.buildingId})) ||
            (previousRoom && (!previousRoom.exists || previousRoom.data().organizationId!==orgId || !allows(actor,'manageLease',{...scope,buildingId:previousRoom.data().buildingId})))) fail('permission-denied','booking_access_denied');
        if ((!old || old.roomId !== next.roomId) && roomBlocked(room.data())) fail('failed-precondition','room_has_open_problem');
      }
      if (input.create && old) return {id:ref.id};
      if(v2&&(next.isMainTenant===false||old?.isMainTenant===false)&&(!old||['roomId','mainTenantId','isMainTenant','status','moveInDate','moveOutDate','monthlyRent','monthlyRentMinor','deposit','contractStartDate','contractEndDate'].some(k=>comparable(old[k])!==comparable(next[k]))))fail('failed-precondition','roommate_dedicated_workflow_required');
      if(v2&&(['rentSchedule','rentTimeZone'].some(k=>Object.hasOwn(patch,k))||(old&&['monthlyRent','monthlyRentMinor'].some(k=>comparable(old[k])!==comparable(next[k])))))fail('failed-precondition','tenant_rent_dedicated_workflow_required');
      if(v2&&old?.isMainTenant===true&&['roomId','status','moveInDate','moveOutDate','isMainTenant'].some(k=>comparable(old[k])!==comparable(next[k]))){
        const linked=await tx.get(db.collection('tenants').where('mainTenantId','==',ref.id));
        if(linked.docs.some(doc=>['active','suspended'].includes(doc.data().status)))fail('failed-precondition','lease_linked_roommates_require_review');
      }
      if(v2&&['occupancyStartDate','contractEndLocalDate','contractEndTimeZone','moveOutLocalDate','moveOutTimeZone'].some(k=>Object.hasOwn(patch,k)))fail('failed-precondition','lease_dedicated_workflow_required');
      if(v2&&old&&['roomId','buildingId','moveOutDate','contractEndDate','status'].some(k=>comparable(old[k])!==comparable(next[k])))fail('failed-precondition','lease_dedicated_workflow_required');
      if (!['active','inactive','suspended','moveOut'].includes(next.status) || typeof next.fullName !== 'string' || !next.fullName.trim()) fail('invalid-argument','booking_invalid_request');
      if (v2 && ['active','suspended'].includes(next.status) && false) fail('failed-precondition','lease_room_not_monthly');// 2026-10-04: every room takes leases
      const start=ms(next.moveInDate), end=next.moveOutDate ? ms(next.moveOutDate) : Infinity;
      if (!Number.isFinite(start) || end <= start) fail('invalid-argument','booking_invalid_dates');
      const now=Timestamp.now();
      let datePolicy;
      if(v2){
        // These fields are server-owned, even through the older broad patch API.
        delete next.backdateReason;
        for(const k of ['moveInLocalDate','moveInTimeZone']){
          if(old?.[k]!==undefined)next[k]=old[k];else delete next[k];
        }
        if(!old||start!==ms(old.moveInDate)){
          const building=await tx.get(db.collection('buildings').doc(room.data().buildingId));
          if(!building.exists||building.data().organizationId!==orgId)fail('not-found','lease_property_not_found');
          datePolicy=leaseDatePolicy({moveInMillis:start,nowMillis:now.toMillis(),timeZone:building.data().timeZone,canBackdate:allows(member.data(),'backdateRecords',{organizationId:orgId,userId:context.auth.uid}),reason:patch.backdateReason});
          if(datePolicy.error)fail(datePolicy.error,datePolicy.key);
          next.moveInLocalDate=datePolicy.localDate;next.moveInTimeZone=datePolicy.timeZone;
        }else if(Object.hasOwn(patch,'backdateReason')){
          fail('invalid-argument','lease_backdate_reason_without_date_change');
        }
      }
      if (next.status === 'active') {
        const bookings=await tx.get(db.collection('bookings').where('roomId','==',next.roomId));
        for (const doc of bookings.docs) {
          const b=doc.data();
          if (ACTIVE.has(b.status) && overlaps(start,end,ms(b.startTime),ms(b.endTime))) fail('already-exists','booking_conflict');
        }
      }
      if(v2&&next.isMainTenant!==false&&['active','suspended'].includes(next.status)){
        const occupants=await tx.get(db.collection('tenants').where('roomId','==',next.roomId));
        for(const doc of occupants.docs){
          if(doc.id===ref.id)continue;
          const t=doc.data();
          if(old&&t.isMainTenant===false&&t.mainTenantId===ref.id)continue;
          if(['active','suspended'].includes(t.status)&&overlaps(start,end,ms(t.moveInDate),t.moveOutDate?ms(t.moveOutDate):Infinity))fail('already-exists','lease_room_occupied');
        }
      }
      next.organizationId=orgId;next.buildingId=room.data().buildingId;
      next.currency=old?.currency || room.data().currency || 'VND';
      next.createdAt=old?.createdAt || now;next.updatedAt=now;
      next.createdBy=old?.createdBy || context.auth.uid;next.updatedBy=context.auth.uid;
      tx.update(roomRef,{bookingRevision:FieldValue.increment(1)});
      if (previousRoom?.exists) tx.update(previousRoom.ref,{bookingRevision:FieldValue.increment(1)});
      tx.set(ref,next);
      if(datePolicy?.backdated){
        // Private immutable evidence; the general activity projection omits it.
        tx.create(db.collection('leaseDateCorrections').doc(),{organizationId:orgId,buildingId:room.data().buildingId,tenantId:ref.id,actorId:context.auth.uid,createdAt:now,previousMoveInDate:old?.moveInDate??null,moveInDate:next.moveInDate,localDate:datePolicy.localDate,timeZone:datePolicy.timeZone,reason:datePolicy.reason});
      }
      if(v2) auditOperation(db,tx,{organizationId:orgId,actorId:context.auth.uid,action:!old?'lease_create':old.roomId!==next.roomId?'lease_move':old.status!==next.status?'lease_status':'lease_edit',targetId:ref.id,old,next,createdAt:next.updatedAt});
      return {id:ref.id};
    });
  };
}
module.exports.createTenantHandler=createTenantHandler;
