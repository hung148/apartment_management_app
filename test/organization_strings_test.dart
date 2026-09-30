import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phan_mem_quan_ly_can_ho/utils/localizations/app_localizations.dart';

void main() {
  // Regression: 'restore_days_left' used {days} while textWithParams fills {{days}}.
  test('organization restore text fills its day count in both languages', () {
    for (final code in ['en', 'vi']) {
      final t = AppTranslations(Locale(code));
      final text = t.textWithParams('restore_days_left', {'days': 12});
      expect(text, contains('12'), reason: code);
      expect(text.contains('{') || text.contains('}'), isFalse, reason: code);
    }
  });

  test('new organization settings strings exist in both languages', () {
    const keys = [
      'org_settings_load_failed', 'close_org_v2_notice', 'org_copy_target_not_allowed',
      'org_copy_cross_link', 'org_copy_try_again', 'recently_deleted_orgs',
      'recently_deleted_empty', 'restore_action', 'restore_days_left',
      'org_restored_success', 'org_restore_failed', 'type_name_to_confirm',
      'activity_action_updateOrganization', 'activity_action_leaveOrganization',
      'activity_action_closeOrganization', 'activity_action_restoreOrganization',
      'copy_target_org', 'copy_no_target_orgs', 'copy_repeat_note',
      'team_waiting_role', 'org_waiting_message', 'team_invitation_role_removed', 'team_role_viewer',
    ];
    for (final code in ['en', 'vi']) {
      final t = AppTranslations(Locale(code));
      for (final key in keys) {
        expect(t.translationKeys, contains(key), reason: '$code:$key');
      }
      expect(t.text('org_copy_target_not_allowed').toLowerCase(), isNot(contains('version')));
    }
  });
  test('account deletion strings exist and fill their placeholders', () {
    const keys = [
      'account_delete_intro', 'account_delete_plan_leave', 'account_delete_plan_close',
      'account_delete_plan_close_members', 'account_delete_plan_decide', 'account_delete_hand_over',
      'account_delete_hand_over_hint', 'account_delete_close_for_everyone', 'account_delete_personal_data',
      'account_delete_choose_first', 'account_delete_plan_changed', 'account_delete_login_left',
      'activity_action_transferOwnership', 'loading', 'incorrect_password', 'account_deletion_failed',
    ];
    for (final code in ['en', 'vi']) {
      final t = AppTranslations(Locale(code));
      for (final key in keys) {
        expect(t.translationKeys, contains(key), reason: '$code:$key');
      }
      final members = t.textWithParams('account_delete_plan_close_members', {'count': 3});
      final handOver = t.textWithParams('account_delete_hand_over', {'name': 'Lan'});
      for (final text in [members, handOver]) {
        expect(text.contains('{') || text.contains('}'), isFalse, reason: code);
      }
      expect(members, contains('3'));
      expect(handOver, contains('Lan'));
    }
  });
  test('personal information strings exist and fill their placeholders', () {
    const keys = [
      'personal_info', 'profile_name', 'profile_name_helper', 'profile_name_invalid', 'profile_phone_helper',
      'profile_phone_invalid', 'profile_change', 'profile_saved', 'profile_save_failed', 'profile_load_failed',
      'profile_change_email', 'profile_change_email_intro', 'profile_new_email', 'profile_current_password',
      'profile_send_link', 'profile_email_same', 'profile_email_invalid', 'profile_email_in_use',
      'profile_email_link_sent', 'profile_change_password', 'profile_new_password', 'profile_confirm_password',
      'profile_password_same', 'profile_password_mismatch', 'profile_password_changed',
      'profile_too_many_attempts', 'profile_network_error', 'phone', 'email', 'password_hint',
      'auth_password_too_weak', 'incorrect_password', 'save', 'close',
      'auth_forgot_password', 'auth_reset_title', 'auth_reset_intro', 'auth_reset_send', 'auth_reset_sent',
      'auth_reset_failed', 'profile_forgot_current_password', 'profile_reset_link_sent', 'cancel',
    ];
    for (final code in ['en', 'vi']) {
      final t = AppTranslations(Locale(code));
      for (final key in keys) {
        expect(t.translationKeys, contains(key), reason: '$code:$key');
      }
      final sent = t.textWithParams('profile_email_link_sent', {'email': 'new@x.co', 'current': 'old@x.co'});
      final intro = t.textWithParams('profile_change_email_intro', {'email': 'old@x.co'});
      final reset = t.textWithParams('auth_reset_sent', {'email': 'a@x.co'});
      final resetSignedIn = t.textWithParams('profile_reset_link_sent', {'email': 'a@x.co'});
      for (final text in [sent, intro, reset, resetSignedIn]) {
        expect(text.contains('{') || text.contains('}'), isFalse, reason: code);
      }
      expect(sent, allOf(contains('new@x.co'), contains('old@x.co')));
    }
  });
}
