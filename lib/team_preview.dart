import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'preview/team_preview_store.dart';
import 'screens/team/team_screen.dart';
import 'screens/team/invitation_acceptance.dart';
import 'screens/team/access_request.dart';
import 'screens/team/role_workspace.dart';
import 'models/team_access.dart';
import 'utils/app_theme.dart';
import 'utils/localizations/app_localizations.dart';

void main() => runApp(const TeamPreviewApp());

/// Separate entry point: no Firebase initialization or production services.
class TeamPreviewApp extends StatefulWidget {
  const TeamPreviewApp({super.key});
  @override
  State<TeamPreviewApp> createState() => _TeamPreviewAppState();
}

class _TeamPreviewAppState extends State<TeamPreviewApp> {
  var store = TeamPreviewStore()..addOperationalSamples();
  var vietnamese = false;
  var recipient = false;
  var requesting = false;
  var workspace = false;
  var generation = 0;
  @override
  Widget build(BuildContext context) => MaterialApp(
    theme: buildAppTheme(),
    locale: Locale(vietnamese ? 'vi' : 'en'),
    supportedLocales: const [Locale('en'), Locale('vi')],
    localizationsDelegates: const [
      AppTranslationsDelegate(),
      ...GlobalMaterialLocalizations.delegates,
    ],
    home: Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Builder(
              builder: (context) => ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * .45,
                ),
                child: SingleChildScrollView(
                  child: ExpansionTile(
                    initiallyExpanded: false,
                    title: Text(
                      vietnamese
                          ? 'Bản xem thử • Dữ liệu mẫu'
                          : 'Local preview • Sample data',
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          vietnamese
                              ? 'Không kết nối Firebase. Tải lại sẽ xóa thay đổi. Mã lời mời: demo-invite. Chế độ người nhận mô phỏng tài khoản đã xác minh.'
                              : 'No Firebase connection. Reload discards changes. Invitation reference: demo-invite. Recipient mode simulates a verified account.',
                        ),
                      ),
                      Wrap(
                        // Preview-only controls use the same policy as real reads.
                        spacing: 8,
                        children: [
                          DropdownButton<String>(
                            value: TeamPolicy.templateIds.contains(store.workspaceRole)
                                ? store.workspaceRole
                                : 'owner',
                            items: TeamPolicy.templateIds
                                .map(
                                  (r) => DropdownMenuItem(
                                    value: r,
                                    child: Text(
                                      AppTranslations(
                                        Locale(vietnamese ? 'vi' : 'en'),
                                      )['team_role_$r'],
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (role) => setState(() {
                              store.workspaceRole = role!;
                              workspace = true;
                              recipient = false;
                              requesting = false;
                              generation++;
                            }),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              store.assignedOnly = !store.assignedOnly;
                              workspace = true;
                              recipient = false;
                              requesting = false;
                              generation++;
                            }),
                            child: Text(
                              store.assignedOnly
                                  ? (vietnamese
                                        ? 'Tất cả cơ sở'
                                        : 'Show all properties')
                                  : (vietnamese
                                        ? 'Chỉ Riverside'
                                        : 'Assign Riverside only'),
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              recipient = !recipient;
                              requesting = false;
                              workspace = false;
                              store.workspaceRole = 'owner';
                              store.assignedOnly = false;
                              generation++;
                            }),
                            child: Text(
                              recipient
                                  ? (vietnamese
                                        ? 'Mở chủ sở hữu'
                                        : 'Open owner')
                                  : (vietnamese
                                        ? 'Mở người nhận'
                                        : 'Open recipient'),
                            ),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              requesting = !requesting;
                              workspace = false;
                              store.workspaceRole = 'owner';
                              store.assignedOnly = false;
                              recipient = false;
                              generation++;
                            }),
                            child: Text(
                              requesting
                                  ? (vietnamese
                                        ? 'Mở chủ sở hữu'
                                        : 'Open owner')
                                  : (vietnamese
                                        ? 'Mở người yêu cầu'
                                        : 'Open requester'),
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                setState(() => vietnamese = !vietnamese),
                            child: Text(vietnamese ? 'English' : 'Tiếng Việt'),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              store = TeamPreviewStore()
                                ..addOperationalSamples();
                              generation++;
                            }),
                            child: Text(
                              vietnamese
                                  ? 'Đặt lại dữ liệu mẫu'
                                  : 'Reset sample data',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: workspace
                  ? RoleWorkspace(
                      key: ValueKey(generation),
                      organizationId: 'preview',
                      service: store.service,
                    )
                  : requesting
                  ? AccessRequestScreen(
                      key: ValueKey(generation),
                      service: store.service,
                      onBack: () => setState(() {
                        requesting = false;
                        generation++;
                      }),
                    )
                  : recipient
                  ? InvitationAcceptance(
                      key: ValueKey(generation),
                      service: store.service,
                      onBack: () => setState(() {
                        recipient = false;
                        generation++;
                      }),
                    )
                  : TeamScreen(
                      key: ValueKey(generation),
                      organizationId: 'preview',
                      service: store.service,
                    ),
            ),
          ],
        ),
      ),
    ),
  );
}
