import 'package:flutter/material.dart';

class AppTranslations {
  final Locale locale;
  AppTranslations(this.locale);

  static AppTranslations of(BuildContext context) {
    return Localizations.of<AppTranslations>(context, AppTranslations)!;
  }

  static final Map<String, Map<String, String>> _values = {
    'vi': {
      'lang': 'ngôn ngữ',
      'select_language': 'Chọn ngôn ngữ',
      'vietnamese': 'Tiếng Việt',
      'english': 'Tiếng Anh',
      'dashboard': 'Trang chủ',
      'logout': 'Đăng xuất',
      'update': 'Cập nhật',
      'your_organizations': 'Tổ Chức Của Bạn',
      'join': 'Tham gia',
      'tooltip_join': 'Tham gia tổ chức',
      'create': 'Tạo mới',
      'tooltip_create': 'Tạo tổ chức mới',
      'no_orgs': 'Chưa có tổ chức nào',
      'no_orgs_sub': 'Tạo tổ chức mới hoặc tham gia bằng mã mời',
      'hello': 'Xin chào!',
      'joined_at': 'Tham gia',
      'admin': 'Quản trị viên',
      'member': 'Thành viên',
      'available_update': 'Cập nhật có sẵn',
      'new_update_ready': 'Phiên bản mới đã sẵn sàng!',
      'click_update_button': 'Nhấn "Tải xuống" để mở trang tải xuống phiên bản mới.',
      'later': 'Để sau',
      'download': 'Tải xuống',
      'opening_download_page': 'Đang mở trang tải xuống...',
      'cannot_open_browser': 'Không thể mở trình duyệt. Vui lòng kiểm tra kết nối.',
      'updating': 'Đang cập nhật...',
      'update_success': 'Cập nhật thành công!',
      'update_failed': 'Không thể cập nhật. Vui lòng thử lại sau.',
      'org_name_required': 'Tên tổ chức *',
      'org_name_example': 'VD: Chung cư ABC',
      'please_enter_org_name': 'Vui lòng nhập tên tổ chức',
      'address': 'Địa chỉ',
      'address_example': 'VD: 123 Nguyễn Huệ, Q1, TP.HCM',
      'optional_on_invoice': 'Tùy chọn - Hiển thị trên hóa đơn',
      'phone': 'Số điện thoại',
      'phone_example': 'VD: 028-1234-5678',
      'email': 'Email',
      'email_example': 'VD: contact@abc.com',
      'email_invalid': 'Email không hợp lệ',
      'contact_info_on_invoice': 'Thông tin liên hệ sẽ hiển thị trên hóa đơn PDF',
      'cancel': 'Huỷ',
      'org_created_success': 'Tạo tổ chức thành công!',
      'create_action': 'Tạo',
      'enter_invite_code': 'Nhập mã mời 8 ký tự để tham gia tổ chức',
      'invite_code': 'Mã mời',
      'invite_code_example': 'VD: A3F7B2C9',
      'invite_code_8_chars': 'Mã mời phải có 8 ký tự',
      'join_org_success': 'Tham gia tổ chức thành công!',
      'invite_code_invalid': 'Mã mời không hợp lệ hoặc bạn đã là thành viên',
      'leave_org': 'Rời khỏi tổ chức',
      'leave_org_confirm': 'Bạn có chắc chắn muốn rời khỏi tổ chức "{{name}}"?',
      'lose_access_warning': 'Bạn sẽ mất quyền truy cập vào tất cả dữ liệu của tổ chức này.',
      'leave_action': 'Rời khỏi',
      'leaving_org': 'Đang rời khỏi tổ chức...',
      'left_org_success': 'Đã rời khỏi tổ chức thành công!',
      'cannot_leave_org': 'Không thể rời khỏi tổ chức. Bạn có thể là quản trị viên cuối cùng.',
      'delete_org': 'Xóa tổ chức',
      'delete_org_warning': 'Hành động này sẽ XÓA VĨNH VIỄN tổ chức "{{name}}" và TẤT CẢ dữ liệu liên quan bao gồm:',
      'all_buildings': 'Tất cả tòa nhà',
      'all_rooms': 'Tất cả phòng',
      'all_tenants': 'Tất cả người thuê',
      'all_payments': 'Tất cả thanh toán',
      'all_members': 'Tất cả thành viên',
      'warning_cannot_undo': 'CẢNH BÁO: Hành động này KHÔNG THỂ HOÀN TÁC!',
      'confirm_enter_org_name': 'Để xác nhận, vui lòng nhập tên tổ chức:',
      'name_mismatch': 'Tên không khớp',
      'delete_permanently': 'XÓA VĨNH VIỄN',
      'deleting_org': 'Đang xóa tổ chức...',
      'please_dont_close': 'Vui lòng không đóng ứng dụng',
      'deleted_org_success': 'Đã xóa tổ chức thành công!',
      'cannot_delete_org': 'Không thể xóa tổ chức. Vui lòng thử lại.',
      'org_info': 'Thông tin tổ chức',
      'org_name_label': 'Tên tổ chức:',
      'created_date': 'Ngày tạo:',
      'id': 'ID:',
      'last_updated': 'Cập nhật lần cuối:',
      'address_label': 'Địa chỉ:',
      'phone_label': 'Số điện thoại:',
      'email_label': 'Email:',
      'bank_name': 'Tên ngân hàng:',
      'account_number': 'Số tài khoản:',
      'account_holder': 'Chủ tài khoản:',
      'tax_code': 'Mã số thuế:',
      'close': 'Đóng',
      'migrate_and_delete': 'Di chuyển & xóa tổ chức',
      'migrate_org_data': 'Di chuyển dữ liệu tổ chức',
      'source_org_info': 'Thông tin tổ chức nguồn:',
      'name_with_value': 'Tên: {{name}}',
      'id_with_value': 'ID: {{id}}',
      'target_org_id': 'ID tổ chức đích',
      'enter_target_org_id': 'Nhập ID tổ chức đích nơi muốn di chuyển',
      'target_org_id_placeholder': 'ID của tổ chức đích (không phải tên)',
      'preview_data_migrate': 'Xem trước dữ liệu sẽ di chuyển:',
      'preview_stats': 'Tòa nhà: {{buildings}}, Phòng: {{rooms}}, Người thuê: {{tenants}}, Thanh toán: {{payments}}',
      'please_enter_target_id': 'Vui lòng nhập ID tổ chức đích.',
      'fetching_preview': 'Đang lấy xem trước...',
      'fetched_preview': 'Đã lấy xem trước.',
      'preview_error': 'Lỗi khi lấy xem trước: {{error}}',
      'preview': 'Xem trước',
      'migrating_and_deleting': 'Đang di chuyển và xóa...',
      'migrating_data': 'Đang di chuyển dữ liệu...',
      'error': 'Lỗi: {{error}}',
      'migrated_and_deleted_success': 'Đã di chuyển và xóa tổ chức thành công!',
      'migrated_data_success': 'Đã di chuyển dữ liệu thành công!',
      'operation_failed': 'Thao tác thất bại.',
      'migrate_and_delete_action': 'Di chuyển & XÓA',
      'migrate_action': 'Di chuyển',
      'open_org': 'Mở tổ chức',
      'view_org_info': 'Xem thông tin tổ chức',
      'org_details_and_id': 'Chi tiết tổ chức và ID',
      'migrate_to_other_org': 'Di chuyển dữ liệu sang tổ chức khác',
      'copy_all_data': 'Sao chép toàn bộ dữ liệu sang tổ chức khác',
      'migrate_and_delete_org': 'Di chuyển & xóa tổ chức',
      'transfer_and_delete': 'Chuyển dữ liệu và xóa tổ chức này',
      'delete_org_action': 'Xóa tổ chức',
      'delete_org_permanently': 'Xóa vĩnh viễn tổ chức và tất cả dữ liệu',
      'leave_org_action': 'Rời khỏi tổ chức',
      'will_lose_access': 'Bạn sẽ mất quyền truy cập',
      'confirm_logout': 'Xác nhận đăng xuất',
      'confirm_logout_message': 'Bạn có chắc chắn muốn đăng xuất?',
      'window_size_too_small': 'Kích thước cửa sổ quá nhỏ',
      'minimum_size': 'Kích thước tối thiểu: {{width}}x{{height}}',
      'current_size': 'Hiện tại: {{width}}x{{height}}',
      'user_data_not_found': 'Không tìm thấy dữ liệu người dùng',
      'logout_action': 'Đăng xuất',
      'org_options': 'Tùy chọn tổ chức',
    },
    'en': {
      'lang': 'language',
      'select_language': 'Select Language',
      'vietnamese': 'Vietnamese',
      'english': 'English',
      'dashboard': 'Dashboard',
      'logout': 'Logout',
      'update': 'Update',
      'your_organizations': 'Your Organizations',
      'join': 'Join',
      'tooltip_join': 'Join an existing organization',
      'create': 'Create',
      'tooltip_create': 'Create a new organization',
      'no_orgs': 'No organizations yet',
      'no_orgs_sub': 'Create a new organization or join with an invite code',
      'hello': 'Hello!',
      'joined_at': 'Joined',
      'admin': 'Admin',
      'member': 'Member',
      'available_update': 'Update is available',
      'new_update_ready': 'New Update is ready!',
      'click_update_button': 'Click "Download" to open the page for downloading the new version.',
      'later': 'Later',
      'download': 'Download',
      'opening_download_page': 'Opening download page...',
      'cannot_open_browser': 'Cannot open browser. Please check your connection.',
      'updating': 'Updating...',
      'update_success': 'Update successful!',
      'update_failed': 'Cannot update. Please try again later.',
      'org_name_required': 'Organization Name *',
      'org_name_example': 'E.g.: ABC Apartment',
      'please_enter_org_name': 'Please enter organization name',
      'address': 'Address',
      'address_example': 'E.g.: 123 Main St, District 1, HCMC',
      'optional_on_invoice': 'Optional - Display on invoice',
      'phone': 'Phone Number',
      'phone_example': 'E.g.: 028-1234-5678',
      'email': 'Email',
      'email_example': 'E.g.: contact@abc.com',
      'email_invalid': 'Invalid email',
      'contact_info_on_invoice': 'Contact information will be displayed on PDF invoice',
      'cancel': 'Cancel',
      'org_created_success': 'Organization created successfully!',
      'create_action': 'Create',
      'enter_invite_code': 'Enter 8-character invite code to join organization',
      'invite_code': 'Invite Code',
      'invite_code_example': 'E.g.: A3F7B2C9',
      'invite_code_8_chars': 'Invite code must be 8 characters',
      'join_org_success': 'Joined organization successfully!',
      'invite_code_invalid': 'Invalid invite code or you are already a member',
      'leave_org': 'Leave Organization',
      'leave_org_confirm': 'Are you sure you want to leave "{{name}}"?',
      'lose_access_warning': 'You will lose access to all data of this organization.',
      'leave_action': 'Leave',
      'leaving_org': 'Leaving organization...',
      'left_org_success': 'Left organization successfully!',
      'cannot_leave_org': 'Cannot leave organization. You may be the last admin.',
      'delete_org': 'Delete Organization',
      'delete_org_warning': 'This action will PERMANENTLY DELETE organization "{{name}}" and ALL related data including:',
      'all_buildings': 'All buildings',
      'all_rooms': 'All rooms',
      'all_tenants': 'All tenants',
      'all_payments': 'All payments',
      'all_members': 'All members',
      'warning_cannot_undo': 'WARNING: This action CANNOT BE UNDONE!',
      'confirm_enter_org_name': 'To confirm, please enter the organization name:',
      'name_mismatch': 'Name does not match',
      'delete_permanently': 'DELETE PERMANENTLY',
      'deleting_org': 'Deleting organization...',
      'please_dont_close': 'Please do not close the app',
      'deleted_org_success': 'Organization deleted successfully!',
      'cannot_delete_org': 'Cannot delete organization. Please try again.',
      'org_info': 'Organization Information',
      'org_name_label': 'Organization Name:',
      'created_date': 'Created Date:',
      'id': 'ID:',
      'last_updated': 'Last Updated:',
      'address_label': 'Address:',
      'phone_label': 'Phone:',
      'email_label': 'Email:',
      'bank_name': 'Bank Name:',
      'account_number': 'Account Number:',
      'account_holder': 'Account Holder:',
      'tax_code': 'Tax Code:',
      'close': 'Close',
      'migrate_and_delete': 'Migrate & Delete Organization',
      'migrate_org_data': 'Migrate Organization Data',
      'source_org_info': 'Source organization information:',
      'name_with_value': 'Name: {{name}}',
      'id_with_value': 'ID: {{id}}',
      'target_org_id': 'Target Organization ID',
      'enter_target_org_id': 'Enter target organization ID where you want to migrate',
      'target_org_id_placeholder': 'ID of target organization (not name)',
      'preview_data_migrate': 'Preview data to migrate:',
      'preview_stats': 'Buildings: {{buildings}}, Rooms: {{rooms}}, Tenants: {{tenants}}, Payments: {{payments}}',
      'please_enter_target_id': 'Please enter target organization ID.',
      'fetching_preview': 'Fetching preview...',
      'fetched_preview': 'Preview fetched.',
      'preview_error': 'Error fetching preview: {{error}}',
      'preview': 'Preview',
      'migrating_and_deleting': 'Migrating and deleting...',
      'migrating_data': 'Migrating data...',
      'error': 'Error: {{error}}',
      'migrated_and_deleted_success': 'Organization migrated and deleted successfully!',
      'migrated_data_success': 'Data migrated successfully!',
      'operation_failed': 'Operation failed.',
      'migrate_and_delete_action': 'Migrate & DELETE',
      'migrate_action': 'Migrate',
      'open_org': 'Open Organization',
      'view_org_info': 'View Organization Info',
      'org_details_and_id': 'Organization details and ID',
      'migrate_to_other_org': 'Migrate data to another organization',
      'copy_all_data': 'Copy all data to another organization',
      'migrate_and_delete_org': 'Migrate & delete organization',
      'transfer_and_delete': 'Transfer data and delete this organization',
      'delete_org_action': 'Delete Organization',
      'delete_org_permanently': 'Permanently delete organization and all data',
      'leave_org_action': 'Leave Organization',
      'will_lose_access': 'You will lose access',
      'confirm_logout': 'Confirm Logout',
      'confirm_logout_message': 'Are you sure you want to logout?',
      'window_size_too_small': 'Window size too small',
      'minimum_size': 'Minimum size: {{width}}x{{height}}',
      'current_size': 'Current: {{width}}x{{height}}',
      'user_data_not_found': 'User data not found',
      'logout_action': 'Logout',
      'org_options': 'Organization Options',
    },
  };

  String text(String key) => _values[locale.languageCode]?[key] ?? key;
  String operator [](String key) => text(key);

  // Method to handle dynamic values with named parameters
  String textWithParams(String key, Map<String, dynamic> params) {
    String template = text(key);
    params.forEach((key, value) {
      template = template.replaceAll('{{$key}}', value.toString());
    });
    return template;
  }
}

// Delegate để Flutter nhận diện bộ từ điển này
class AppTranslationsDelegate extends LocalizationsDelegate<AppTranslations> {
  const AppTranslationsDelegate();

  @override
  bool isSupported(Locale locale) => ['vi', 'en'].contains(locale.languageCode);

  @override
  Future<AppTranslations> load(Locale locale) async => AppTranslations(locale);

  @override
  bool shouldReload(AppTranslationsDelegate old) => false;
}

/* Usage Examples:
// Simple translation (no parameters)
Text(AppTranslations.of(context)['logout'])

// Translation with parameters
Text(
  AppTranslations.of(context).textWithParams(
    'leave_org_confirm',
    {'name': org.name}
  )
)

Text(
  AppTranslations.of(context).textWithParams(
    'delete_org_warning',
    {'name': org.name}
  )
)

Text(
  AppTranslations.of(context).textWithParams(
    'preview_stats',
    {
      'buildings': preview?['buildings'] ?? 0,
      'rooms': preview?['rooms'] ?? 0,
      'tenants': preview?['tenants'] ?? 0,
      'payments': preview?['payments'] ?? 0,
    }
  )
)

Text(
  AppTranslations.of(context).textWithParams(
    'minimum_size',
    {
      'width': minWidth.toInt(),
      'height': minHeight.toInt(),
    }
  )
)

Text(
  AppTranslations.of(context).textWithParams(
    'error',
    {'error': e.toString()}
  )
)
*/