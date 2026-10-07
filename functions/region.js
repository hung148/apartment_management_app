'use strict';
// Where the server functions run (2026-10-06, Tom: speed). The Firestore
// databases of both projects are in asia-southeast1 (Singapore); functions in
// us-central1 paid two trips across the Pacific for every read. The app calls
// this region too (lib/services/app_functions.dart).
module.exports={REGION:'asia-southeast1'};
