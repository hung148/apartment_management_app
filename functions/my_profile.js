'use strict';
const {forEachMatch}=require('./org_data');

// "Personal information" in Settings.
// update: name (required) and phone (optional) on owners/{uid}; the new name is
//   copied to every open membership (legacy and version 2) and pending access
//   request, so teammates see it. Staff profiles are the organization's own
//   records and are left for administrators to edit.
// syncEmail: after the user confirmed a new sign-in email (Firebase link), copy
//   the verified email from the ID token to the profile, memberships and
//   pending requests. Safe to call any number of times.
const NAME_MAX=100,PHONE_MAX=30;

function createMyProfileHandler({db,Timestamp,HttpsError}){
 const fail=(code,key)=>{throw new HttpsError(code,key);};
 const cleanName=v=>{
  if(typeof v!=='string')fail('invalid-argument','profile_name_invalid');
  const s=v.replace(/\s+/g,' ').trim();
  // eslint-disable-next-line no-control-regex
  if(!s||s.length>NAME_MAX||/[\u0000-\u001f\u007f]/.test(s))fail('invalid-argument','profile_name_invalid');
  return s;
 };
 const cleanPhone=v=>{
  if(v===null||v===undefined)return null;
  if(typeof v!=='string')fail('invalid-argument','profile_phone_invalid');
  const s=v.trim();
  if(!s)return null;
  const digits=s.replace(/\D/g,'').length;
  if(s.length>PHONE_MAX||!/^\+?[0-9 ().-]+$/.test(s)||digits<8||digits>15)fail('invalid-argument','profile_phone_invalid');
  return s;
 };

 /** Applies [fields] to every open membership and pending request of [uid]. */
 async function copyToTeam(uid,membershipFields,requestFields,now){
  const refs=[];
  const stale=(doc,fields)=>Object.entries(fields).some(([k,v])=>doc.data()[k]!==v);
  await forEachMatch(db,'memberships','ownerId',uid,doc=>{if(doc.data().status!=='revoked'&&stale(doc,membershipFields))refs.push([doc.ref,membershipFields]);});
  await forEachMatch(db,'teamRequests','userId',uid,doc=>{if(doc.data().status==='pending'&&stale(doc,requestFields))refs.push([doc.ref,requestFields]);});
  for(let i=0;i<refs.length;i+=400){
   const batch=db.batch();
   for(const [ref,fields] of refs.slice(i,i+400))batch.update(ref,{...fields,updatedAt:now});
   await batch.commit();
  }
  return refs.length;
 }

 return async request=>{
  const uid=request.auth?.uid;
  if(!uid)fail('unauthenticated','team_sign_in_required');
  const d=request.data||{};
  const allowed={update:['action','name','phone'],syncEmail:['action']}[d.action];
  if(!allowed||Object.keys(d).some(k=>!allowed.includes(k)))fail('invalid-argument','profile_invalid');
  const now=Timestamp.now();
  const ownerRef=db.collection('owners').doc(uid);

  if(d.action==='update'){
   if(!('name' in d))fail('invalid-argument','profile_name_invalid');
   const name=cleanName(d.name),phone=cleanPhone(d.phone);
   await db.runTransaction(async tx=>{
    const cur=await tx.get(ownerRef);
    if(cur.exists)tx.update(ownerRef,{name,phone,updatedAt:now});
    else tx.set(ownerRef,{name,phone,email:request.auth.token?.email??'',createdAt:now,updatedAt:now});
   });
   const updated=await copyToTeam(uid,{displayName:name},{displayName:name},now);
   return {name,phone,updated};
  }

  // syncEmail
  const token=request.auth.token??{};
  if(token.email_verified!==true||typeof token.email!=='string'||!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(token.email))
   fail('failed-precondition','profile_email_not_verified');
  const email=token.email.trim().toLowerCase();
  const cur=await ownerRef.get();
  if(cur.exists&&cur.data().email!==email)await ownerRef.update({email,updatedAt:now});
  const updated=await copyToTeam(uid,{email},{email},now);
  return {email,updated};
 };
}
module.exports={createMyProfileHandler};
