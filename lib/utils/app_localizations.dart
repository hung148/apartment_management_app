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
      'confirm': 'Xác nhận',
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
      'tax_code': 'Mã số thuế',
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
      'day_hint': 'Ngày',
      'month_hint': 'Tháng',
      'year_hint': 'Năm',
      'select_from_calendar': 'Chọn từ lịch',
      'please_enter_date': 'Vui lòng nhập ngày',
      'date_must_be_between': 'Ngày phải từ {{first}} đến {{last}}',
      'buildings_tab': 'Toà nhà',
      'tenants_tab': 'Người thuê',
      'payments_tab': 'Hóa đơn',
      'statistics_tab': 'Thống kê',
      'members_tab': 'Thành viên',
      'add_building': 'Thêm toà nhà',
      'no_buildings': 'Không tìm thấy toà nhà nào',
      'edit': 'Chỉnh sửa',
      'delete': 'Xoá',
      'manage_rooms': 'Quản lý phòng',
      'created_at': 'Tạo lúc',
      'no_payments': 'Chưa có hóa đơn nào',
      'add_payment': 'Thêm Hóa Đơn',
      'add': 'Thêm',
      'search_payments': 'Tìm kiếm hóa đơn...',
      'found_payments': 'Tìm thấy {{count}} hóa đơn',
      'tenant_label': 'Người thuê',
      'amount_label': 'Số tiền',
      'due_date_label': 'Hạn',
      'view_details': 'Xem Chi Tiết',
      'no_data': 'Không có dữ liệu',
      'overview': 'Tổng quan',
      'total_buildings': 'Toà nhà',
      'total_tenants': 'Người thuê',
      'paid_payments': 'Đã thanh toán',
      'pending_payments_label': 'Chưa thanh toán',
      'overdue_payments': 'Quá hạn',
      'total_payments_label': 'Tổng hóa đơn',
      'revenue': 'Doanh thu',
      'collected': 'Đã thu',
      'uncollected': 'Chưa thu',
      'monthly_revenue': 'Doanh thu theo tháng',
      'occupancy_by_building': 'Tỷ lệ lấp đầy theo toà nhà hiện tại',
      'occupancy_trend': 'Xu hướng lấp đầy theo tháng',
      'export_excel': 'Xuất Excel',
      'export_pdf': 'Xuất PDF',
      'filter_by_building': 'Lọc theo toà nhà:',
      'all_buildings_option': 'Tất cả toà nhà',
      'select_building': 'Chọn toà nhà',
      'no_building_data': 'Chưa có dữ liệu toà nhà',
      'occupancy_rate': 'Tỷ lệ lấp đầy (%)',
      'no_building_data_selected': 'Chưa có dữ liệu cho toà nhà này',
      'get_invite_code': 'Lấy mã mời',
      'refresh_code': 'Làm mới mã',
      'refresh_invite_code_title': 'Làm mới mã mời?',
      'refresh_invite_code_body': 'Mã mời cũ sẽ không còn hoạt động nữa. Những người chưa tham gia cần mã mới. Bạn có chắc muốn tiếp tục?',
      'refresh_action': 'Làm mới',
      'code_refreshed': 'Mã mời đã được làm mới',
      'cannot_refresh_code': 'Không thể làm mới mã mời',
      'invite_code_label': 'Mã mời',
      'members_title': 'Thành viên',
      'no_members': 'Không tìm thấy thành viên.',
      'promote_to_admin': 'Thăng cấp Admin',
      'remove_from_org': 'Xóa khỏi tổ chức',
      'confirm_remove': 'Xác nhận xóa',
      'confirm_remove_body': 'Bạn có chắc muốn xóa {{name}} khỏi tổ chức?',
      'member_removed': 'Đã xóa thành viên',
      'promoted_to_admin': 'Đã thăng cấp thành admin',
      'delete_building_title': 'Xóa Toà Nhà',
      'delete_building_confirm': 'Bạn có chắc muốn xóa "{{name}}"?',
      'delete_action_will': 'Thao tác này sẽ:',
      'delete_all_rooms': 'Xóa tất cả phòng trong toà nhà',
      'mark_tenants_moved': 'Đánh dấu {{count}} người thuê là "Đã chuyển đi"',
      'tenant_data_preserved': 'Thông tin người thuê sẽ được lưu giữ để tham khảo',
      'add_building_success': 'Thêm toà nhà thành công',
      'add_building_rooms_success': 'Thêm toà nhà và {{count}} phòng thành công',
      'update_building_success': 'Cập nhật toà nhà thành công',
      'update_building_rooms_success': 'Cập nhật toà nhà và thêm {{count}} phòng thành công',
      'min_window_size': 'Kích thước cửa sổ quá nhỏ',
      'downloading_update': 'Đang tải xuống bản cập nhật',
      'connecting': 'Đang kết nối',
    },
    'en': {
      'lang': 'language',
      'select_language': 'Select Language',
      'vietnamese': 'Vietnamese',
      'english': 'English',
      'confirm': 'Confirm',
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
      'tax_code': 'Tax Code',
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
      'day_hint': 'Day',
      'month_hint': 'Month',
      'year_hint': 'Year',
      'select_from_calendar': 'Pick from calendar',
      'please_enter_date': 'Please enter a date',
      'date_must_be_between': 'Date must be between {{first}} and {{last}}',
      'buildings_tab': 'Buildings',
      'tenants_tab': 'Tenants',
      'payments_tab': 'Payments',
      'statistics_tab': 'Statistics',
      'members_tab': 'Members',
      'add_building': 'Add Building',
      'no_buildings': 'No buildings found',
      'edit': 'Edit',
      'delete': 'Delete',
      'manage_rooms': 'Manage Rooms',
      'created_at': 'Created',
      'no_payments': 'No payments yet',
      'add_payment': 'Add Payment',
      'add': 'Add',
      'search_payments': 'Search payments...',
      'found_payments': 'Found {{count}} payments',
      'tenant_label': 'Tenant',
      'amount_label': 'Amount',
      'due_date_label': 'Due',
      'view_details': 'View Details',
      'no_data': 'No data available',
      'overview': 'Overview',
      'total_buildings': 'Buildings',
      'total_tenants': 'Tenants',
      'paid_payments': 'Paid',
      'pending_payments_label': 'Pending',
      'overdue_payments': 'Overdue',
      'total_payments_label': 'Total Payments',
      'revenue': 'Revenue',
      'collected': 'Collected',
      'uncollected': 'Uncollected',
      'monthly_revenue': 'Monthly Revenue',
      'occupancy_by_building': 'Current Occupancy by Building',
      'occupancy_trend': 'Monthly Occupancy Trend',
      'export_excel': 'Export Excel',
      'export_pdf': 'Export PDF',
      'filter_by_building': 'Filter by building:',
      'all_buildings_option': 'All buildings',
      'select_building': 'Select building',
      'no_building_data': 'No building data yet',
      'occupancy_rate': 'Occupancy rate (%)',
      'no_building_data_selected': 'No data for this building yet',
      'get_invite_code': 'Get Invite Code',
      'refresh_code': 'Refresh Code',
      'refresh_invite_code_title': 'Refresh invite code?',
      'refresh_invite_code_body': 'The old invite code will no longer work. People who haven\'t joined yet will need the new code. Are you sure?',
      'refresh_action': 'Refresh',
      'code_refreshed': 'Invite code refreshed',
      'cannot_refresh_code': 'Cannot refresh invite code',
      'invite_code_label': 'Invite code',
      'members_title': 'Members',
      'no_members': 'No members found.',
      'promote_to_admin': 'Promote to Admin',
      'remove_from_org': 'Remove from organization',
      'confirm_remove': 'Confirm removal',
      'confirm_remove_body': 'Are you sure you want to remove {{name}} from the organization?',
      'member_removed': 'Member removed',
      'promoted_to_admin': 'Promoted to admin',
      'delete_building_title': 'Delete Building',
      'delete_building_confirm': 'Are you sure you want to delete "{{name}}"?',
      'delete_action_will': 'This action will:',
      'delete_all_rooms': 'Delete all rooms in the building',
      'mark_tenants_moved': 'Mark {{count}} tenants as "Moved Out"',
      'tenant_data_preserved': 'Tenant information will be preserved for reference',
      'add_building_success': 'Building added successfully',
      'add_building_rooms_success': 'Building and {{count}} rooms added successfully',
      'update_building_success': 'Building updated successfully',
      'update_building_rooms_success': 'Building updated and {{count}} rooms added successfully',
      'min_window_size': 'Window size too small',
      'downloading_update': 'Downloading update',
      'connecting': 'Connecting',
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

extension DatePickerFormatting on AppTranslations {
  bool get isVietnamese => locale.languageCode == 'vi';
  
  // Returns the appropriate date format pattern
  String get dateFormat => isVietnamese ? 'dd/MM/yyyy' : 'MM/dd/yyyy';
  
  // Format a date in a readable way
  String formatLongDate(DateTime date) {
    if (isVietnamese) {
      return _formatVietnameseDate(date);
    } else {
      return _formatEnglishDate(date);
    }
  }

  String _formatVietnameseDate(DateTime date) {
    final weekdays = [
      'Chủ nhật', 'Thứ hai', 'Thứ ba', 'Thứ tư',
      'Thứ năm', 'Thứ sáu', 'Thứ bảy',
    ];
    
    final weekday = weekdays[date.weekday % 7];
    return '$weekday, ngày ${date.day} tháng ${date.month} năm ${date.year}';
  }

  String _formatEnglishDate(DateTime date) {
    final weekdays = [
      'Sunday', 'Monday', 'Tuesday', 'Wednesday',
      'Thursday', 'Friday', 'Saturday',
    ];
    
    final months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    
    final weekday = weekdays[date.weekday % 7];
    final day = date.day;
    final month = months[date.month - 1];
    final year = date.year;
    
    // Add ordinal suffix (st, nd, rd, th)
    String daySuffix;
    if (day >= 11 && day <= 13) {
      daySuffix = 'th';
    } else {
      switch (day % 10) {
        case 1: daySuffix = 'st'; break;
        case 2: daySuffix = 'nd'; break;
        case 3: daySuffix = 'rd'; break;
        default: daySuffix = 'th';
      }
    }
    
    return '$weekday, $month $day$daySuffix, $year';
  }
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