part of 'organization_screen.dart';

// Member list, invite codes, and member-management actions.
// The main screen owns state, services, and lifecycle.
extension _OrganizationMembers on _OrganizationScreenState {
  // ========================================
  // MEMBERS TAB
  // ========================================
  Widget _buildMembersTab() {
    final t = AppTranslations.of(context);
    return FutureBuilder<List<dynamic>>(
      future: _membersTabFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final members = (snapshot.data?[0] as List<Membership>?) ?? [];
        final myMembership = snapshot.data?[1] as Membership?;
        final isAdmin = myMembership?.role == 'admin';

        final totalMembers = members.length;
        final adminCount = members.where((m) => m.role == 'admin').length;
        final activeCount = members.where((m) => m.status == 'active').length;

        return CustomScrollView(
          slivers: [
            // ── Summary bar ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildMemberSummaryBar(
                      total: totalMembers,
                      admins: adminCount,
                      active: activeCount,
                      t: t,
                    ),
                    const SizedBox(height: 16),

                    // ── Invite card (admin only) ──────────────────────
                    if (isAdmin && myMembership != null)
                      _buildInviteCard(myMembership, t),

                    // ── Section header ────────────────────────────────
                    if (members.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: Row(
                          children: [
                            Text(
                              t['members_tab'].toUpperCase(),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: Colors.grey.shade500,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '$totalMembers ${t['members_tab'].toLowerCase()}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // ── Members list ─────────────────────────────────────────
            if (members.isEmpty)
              SliverFillRemaining(
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.group_outlined,
                          size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text(t['no_members'],
                          style: TextStyle(color: Colors.grey.shade600)),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildMemberCard(
                      member: members[index],
                      myMembership: myMembership,
                      isAdmin: isAdmin,
                      t: t,
                    ),
                    childCount: members.length,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // ── Summary bar ───────────────────────────────────────────────────────────────
  Widget _buildMemberSummaryBar({
    required int total,
    required int admins,
    required int active,
    required AppTranslations t,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          _summaryBarItem(
            value: total.toString(),
            label: t['members_title'],
            color: AppThemePalette.primary,
            isFirst: true,
          ),
          _summaryBarDivider(),
          _summaryBarItem(
            value: admins.toString(),
            label: t['member_role_admin'],
            color: const Color(0xFF854F0B),
          ),
          _summaryBarDivider(),
          _summaryBarItem(
            value: active.toString(),
            label: t['tenant_status_active'],
            color: const Color(0xFF3B6D11),
            isLast: true,
          ),
        ],
      ),
    );
  }

  // ── Invite card ───────────────────────────────────────────────────────────────
  Widget _buildInviteCard(Membership myMembership, AppTranslations t) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 4, color: AppThemePalette.primary),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──────────────────────────────────────────────
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppThemePalette.primaryLight,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child:  Icon(Icons.link_rounded,
                          size: 20, color: AppThemePalette.primary),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            t['get_invite_code'],
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            t['invite_code_label'],
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),

                // ── Code display ─────────────────────────────────────────
                if (inviteCode != null) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppThemePalette.primaryLight,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: AppThemePalette.primary.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: SelectableText(
                            inviteCode!,
                            style:  TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: AppThemePalette.primary,
                              letterSpacing: 3,
                            ),
                          ),
                        ),
                        // ── Copy icon button ─────────────────────────────
                        MouseRegion(
                          onEnter: (_) => _updateOrganizationState(() => _codeHovered = true),
                          onExit: (_) => _updateOrganizationState(() {
                            _codeHovered = false;
                            _codePressed = false;
                          }),
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTapDown: (_) =>
                                _updateOrganizationState(() => _codePressed = true),
                            onTapUp: (_) =>
                                _updateOrganizationState(() => _codePressed = false),
                            onTapCancel: () =>
                                _updateOrganizationState(() => _codePressed = false),
                            onTap: () {
                              Clipboard.setData(
                                  ClipboardData(text: inviteCode!));
                              _updateOrganizationState(() => _codeCopied = true);
                              Future.delayed(const Duration(seconds: 2), () {
                                if (mounted) {
                                  _updateOrganizationState(() => _codeCopied = false);
                                }
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: _codeCopied
                                    ? const Color(0xFF3B6D11)
                                        .withValues(alpha: 0.12)
                                    : _codePressed
                                        ? AppThemePalette.primary
                                            .withValues(alpha: 0.2)
                                        : _codeHovered
                                            ? AppThemePalette.primary
                                                .withValues(alpha: 0.1)
                                            : Colors.transparent,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: AnimatedScale(
                                scale: _codePressed ? 0.88 : 1.0,
                                duration: const Duration(milliseconds: 100),
                                child: Icon(
                                  _codeCopied
                                      ? Icons.check_circle_rounded
                                      : Icons.copy_rounded,
                                  size: 16,
                                  color: _codeCopied
                                      ? const Color(0xFF3B6D11)
                                      : AppThemePalette.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                // ── Action buttons ───────────────────────────────────────
                Row(
                  children: [
                    _footerActionBtn(
                      icon: inviteCode == null
                          ? Icons.vpn_key_rounded
                          : Icons.visibility_off_rounded,
                      label: inviteCode == null
                          ? t['get_invite_code']
                          : t['hide_invite_code'], // add this key to AppTranslations
                      color: AppThemePalette.primary,
                      bgColor: AppThemePalette.primaryLight,
                      onTap: loadingInvite
                          ? () {}
                          : () {
                              if (inviteCode != null) {
                                _updateOrganizationState(() => inviteCode = null);
                              } else {
                                _loadInviteCode();
                              }
                            },
                    ),
                    if (inviteCode != null) ...[
                      const SizedBox(width: 8),
                      _footerActionBtn(
                        icon: _refreshingCode
                            ? Icons.hourglass_top_rounded
                            : Icons.refresh_rounded,
                        label: t['refresh_code'],
                        color: const Color(0xFF854F0B),
                        bgColor: const Color(0xFFFAEEDA),
                        onTap: _refreshingCode
                            ? () {}
                            : () => _confirmRefreshInviteCode(myMembership),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Member card ───────────────────────────────────────────────────────────────
  Widget _buildMemberCard({
    required Membership member,
    required Membership? myMembership,
    required bool isAdmin,
    required AppTranslations t,
  }) {
    final isMe = myMembership != null && member.ownerId == myMembership.ownerId;
    final isAdminMember = member.role == 'admin';
    final isPending = member.status != 'active';

    final displayName = member.displayName.isNotEmpty
        ? member.displayName
        : member.email.isNotEmpty
            ? member.email
            : member.ownerId;

    final initials = _getMemberInitials(displayName);

    final Color accentColor = AppThemePalette.primary;
    final Color avatarBg = AppThemePalette.primaryLight;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // ── Colored top accent ────────────────────────────────────
          Container(height: 2, color: accentColor.withValues(alpha: 0.4)),

          // ── Card body ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar
                Stack(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: avatarBg,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Center(
                        child: Text(
                          initials,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: accentColor,
                          ),
                        ),
                      ),
                    ),
                    if (isPending)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF9F27),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Theme.of(context).colorScheme.surface,
                                width: 2),
                          ),
                        ),
                      )
                    else
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: const Color(0xFF639922),
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: Theme.of(context).colorScheme.surface,
                                width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),

                // Name + role + email
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              displayName,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Role badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 9, vertical: 3),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              isAdminMember
                                  ? t['member_role_admin']
                                  : t['member_role_member'],
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: accentColor,
                              ),
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Text(
                                t['you'],
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (member.email.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          member.email,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 8),
                      // Meta chips
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          _memberInfoChip(
                            icon: isPending
                                ? Icons.hourglass_top_rounded
                                : Icons.check_circle_outline_rounded,
                            text: isPending
                                ? t['member_status_pending']
                                : t['member_status_active'],
                            color: isPending
                                ? const Color(0xFF854F0B)
                                : const Color(0xFF3B6D11),
                          ),
                          if (isAdminMember)
                            _memberInfoChip(
                              icon: Icons.admin_panel_settings_rounded,
                              text: t['member_role_admin'],
                              color: const Color(0xFF854F0B),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Footer actions ────────────────────────────────────────
          if (isAdmin && !isMe && myMembership != null) ...[
            Divider(height: 1, color: Colors.grey.shade100),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  if (member.role == 'member')
                    _footerActionBtn(
                      icon: Icons.arrow_upward_rounded,
                      label: t['promote_to_admin'],
                      color: AppThemePalette.primary,
                      bgColor: AppThemePalette.primaryLight,
                      onTap: () => _promoteMember(member, myMembership, t),
                    ),
                  if (member.role == 'member') const SizedBox(width: 8),
                  _footerActionBtn(
                      icon: Icons.person_remove_outlined,
                      label: t['remove_from_org'],
                      color: const Color(0xFFA32D2D),
                      bgColor: const Color(0xFFFCEBEB),
                      onTap: () => _removeMember(member, myMembership, displayName, t),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Member info chip ──────────────────────────────────────────────────────────
  Widget _memberInfoChip({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color),
        const SizedBox(width: 3),
        Text(text, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }

  // ── Member initials ───────────────────────────────────────────────────────────
  String _getMemberInitials(String name) {
    final words = name.trim().split(' ');
    if (words.isEmpty || words.first.isEmpty) return '?';
    if (words.length == 1) return words[0][0].toUpperCase();
    return (words.first[0] + words.last[0]).toUpperCase();
  }

  // ── Promote action ────────────────────────────────────────────────────────────
  Future<void> _promoteMember(
    Membership member,
    Membership myMembership,
    AppTranslations t,
  ) async {
    final confirm = await _showTrackedDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(t['promote_to_admin']),
        content: Text(t.textWithParams(
            'member_remove_confirm_body', {'name': member.displayName.isNotEmpty ? member.displayName : member.email})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t['cancel'])),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppThemePalette.primary,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t['promote_to_admin']),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final success = await _orgService.promoteMemberToAdmin(
      currentAdminId: myMembership.ownerId,
      memberIdToPromote: member.ownerId,
      orgId: widget.organization.id,
    );
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t['member_promoted_success'])),
      );
      _refreshAll();
    }
  }

  // ── Remove action ─────────────────────────────────────────────────────────────
  Future<void> _removeMember(
    Membership member,
    Membership myMembership,
    String displayName,
    AppTranslations t,
  ) async {
    final confirm = await _showTrackedDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(t['member_remove_confirm_title']),
        content: Text(t.textWithParams(
            'member_remove_confirm_body', {'name': displayName})),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t['cancel'])),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t['delete'],
                style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final success = await _orgService.leaveOrganization(
      member.ownerId,
      widget.organization.id,
    );
    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t['member_removed_success'])),
      );
      _refreshAll();
    }
  }

  // ── Refresh invite code confirm ───────────────────────────────────────────────
  Future<void> _confirmRefreshInviteCode(Membership myMembership) async {
    final t = AppTranslations.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final confirm = await _showTrackedDialog<bool>(
      context: context,
      builder: (ctx) => AppAlertDialog(
        title: Text(t['refresh_invite_code_title']),
        content: Text(t['refresh_invite_code_body']),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(t['cancel'])),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF854F0B),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(t['refresh_action']),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    _updateOrganizationState(() => _refreshingCode = true);
    try {
      final success = await _orgService.refreshInviteCode(
        myMembership.ownerId,
        widget.organization.id,
      );
      if (success && mounted) {
        await _loadInviteCode();
        scaffoldMessenger.showSnackBar(
          SnackBar(
              content: Text(t['code_refreshed']),
              backgroundColor: Colors.green),
        );
      } else if (mounted) {
        scaffoldMessenger.showSnackBar(
          SnackBar(
              content: Text(t['cannot_refresh_code']),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) _updateOrganizationState(() => _refreshingCode = false);
    }
  }


  Future<void> _loadInviteCode() async {
    if (_userId == null) return;
    _updateOrganizationState(() => loadingInvite = true);
    final code = await _orgService.getInviteCode(widget.organization.id);
    _updateOrganizationState(() {
      inviteCode = code;
      loadingInvite = false;
    });
  }

}
