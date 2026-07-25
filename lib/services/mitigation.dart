import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:phan_mem_quan_ly_can_ho/widgets/app_logger.dart';

/// One-time migration: landlordName/landlordPhone/landlordNotes -> renter*
/// Run this ONCE, confirm in Firebase console, then delete this function.
Future<void> migrateLandlordToRenterFields() async {
  final firestore = FirebaseFirestore.instance;
  final buildingsSnapshot = await firestore.collectionGroup('buildings').get();
  // ^ use collectionGroup if buildings live under organizations/{orgId}/buildings
  // if it's a top-level collection instead, use: firestore.collection('buildings').get()

  logger.i('Found ${buildingsSnapshot.docs.length} building docs to check');

  int migrated = 0;
  WriteBatch batch = firestore.batch();
  int batchCount = 0;

  for (final doc in buildingsSnapshot.docs) {
    final data = doc.data();
    final hasOldFields = data.containsKey('landlordName') ||
        data.containsKey('landlordPhone') ||
        data.containsKey('landlordNotes');

    if (!hasOldFields) continue;

    final updates = <String, dynamic>{
      // Only copy over if renter* isn't already populated (don't clobber real data)
      if (data['renterName'] == null && data['landlordName'] != null)
        'renterName': data['landlordName'],
      if (data['renterPhone'] == null && data['landlordPhone'] != null)
        'renterPhone': data['landlordPhone'],
      if (data['renterNotes'] == null && data['landlordNotes'] != null)
        'renterNotes': data['landlordNotes'],
      // Remove the old field names entirely
      'landlordName': FieldValue.delete(),
      'landlordPhone': FieldValue.delete(),
      'landlordNotes': FieldValue.delete(),
    };

    batch.update(doc.reference, updates);
    migrated++;
    batchCount++;

    // Firestore batches max out at 500 writes
    if (batchCount == 450) {
      await batch.commit();
      batch = firestore.batch();
      batchCount = 0;
    }
  }

  if (batchCount > 0) await batch.commit();

  logger.i('Migration complete: $migrated building docs updated');
}