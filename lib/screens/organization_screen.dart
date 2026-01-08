import 'package:apartment_management_project_2/models/buildings_model.dart';
import 'package:apartment_management_project_2/models/membership_model.dart';
import 'package:apartment_management_project_2/models/organization_model.dart';
import 'package:apartment_management_project_2/services/auth_service.dart';
import 'package:apartment_management_project_2/services/building_service.dart';
import 'package:apartment_management_project_2/services/organization_service.dart';
import 'package:flutter/material.dart';

class OrganizationScreen extends StatefulWidget {

  const OrganizationScreen({
    super.key,
  });

  @override
  State<OrganizationScreen> createState() => _OrganizationScreenState();
}

class _OrganizationScreenState extends State<OrganizationScreen> {
  final OrganizationService _orgService = OrganizationService();
  final AuthService _authService = AuthService();
  final BuildingService _buildingService = BuildingService();
  
  late Organization _organization;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _organization =
        ModalRoute.of(context)!.settings.arguments as Organization;
  }

  String? inviteCode;
  bool loadingInvite = false;

  String? get _userId => _authService.currentUser?.uid;

  Future<Membership?> _getMyMembership() {
    if (_userId == null) return Future.value(null);

    return _orgService.getUserMembership(
      _userId!,
      _organization.id,
    );
  }

  Future<List<Membership>> _getMembers() {
    return _orgService.getOrganizationMembers(_organization.id);
  }

  Future<List<Building>> _getBuildings() {
    return _buildingService.getOrganizationBuildings(_organization.id);
  }

  Future<void> _loadInviteCode() async {
    if (_userId == null) return;

    setState(() => loadingInvite = true);

    final code = await _orgService.getInviteCode(
      _userId!,
      _organization.id,
    );

    setState(() {
      inviteCode = code;
      loadingInvite = false;
    });
  }

  // ========================================
  // BUILDING DIALOGS
  // ========================================
  Future<void> _showAddBuildingDialog() async {
    final nameController = TextEditingController();
    final addressController = TextEditingController();

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Building'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Building Name',
                  hintText: 'e.g., Tower A',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  hintText: 'e.g., 123 Main Street',
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.trim().isEmpty ||
                  addressController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Please fill in all fields')),
                );
                return;
              }

              Navigator.of(context).pop({
                'name': nameController.text.trim(),
                'address': addressController.text.trim(),
              });
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );

    if (result != null) {
      final building = Building(
        id: '',
        organizationId: _organization.id,
        name: result['name']!,
        address: result['address']!,
        createdAt: DateTime.now(),
      );

      final buildingId = await _buildingService.addBuilding(building);

      if (buildingId != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Building added successfully')),
        );
        setState(() {}); // Refresh the list
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to add building')),
        );
      }
    }
  }

  Future<void> _showEditBuildingDialog(Building building) async {
    final nameController = TextEditingController(text: building.name);
    final addressController = TextEditingController(text: building.address);

    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Building'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Building Name',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(
                  labelText: 'Address',
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameController.text.trim().isEmpty ||
                  addressController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Please fill in all fields')),
                );
                return;
              }

              Navigator.of(context).pop({
                'name': nameController.text.trim(),
                'address': addressController.text.trim(),
              });
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );

    if (result != null) {
      final success = await _buildingService.updateBuilding(
        building.id,
        {
          'name': result['name'],
          'address': result['address'],
        },
      );

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Building updated successfully')),
        );
        setState(() {}); // Refresh the list
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to update building')),
        );
      }
    }
  }

  Future<void> _deleteBuilding(Building building) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Building'),
        content: Text(
          'Are you sure you want to delete "${building.name}"?\n\n'
          'This will also delete all rooms in this building.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _buildingService.deleteBuildingWithRooms(building.id);

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Building deleted successfully')),
        );
        setState(() {}); // Refresh the list
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete building')),
        );
      }
    }
  }



  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_organization.name),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.apartment), text: 'Buildings'),
              Tab(icon: Icon(Icons.people), text: 'Members'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildBuildingsTab(),
            _buildMembersTab(),
          ],
        ),
      ),
    );
  }

  // ========================================
  // BUILDINGS TAB
  // ========================================

  Widget _buildBuildingsTab() {
    return FutureBuilder<Membership?>(
      future: _getMyMembership(),
      builder: (context, membershipSnapshot) {
        final isAdmin = membershipSnapshot.hasData &&
            membershipSnapshot.data!.role == 'admin';

        return Column(
          children: [
            // Add Building Button (Admin Only)
            if (isAdmin)
              Padding(
                padding: const EdgeInsets.all(16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _showAddBuildingDialog,
                    icon: const Icon(Icons.add),
                    label: const Text('Thêm toà nhà'),
                  ),
                ),
              ),

            // Buildings List
            Expanded(
              child: FutureBuilder<List<Building>>(
                future: _getBuildings(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.apartment, size: 64, color: Colors.grey),
                          SizedBox(height: 16),
                          Text(
                            'Không tìm thấy toà nhà nào',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    );
                  }

                  final buildings = snapshot.data!;

                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: buildings.length,
                    itemBuilder: (context, index) {
                      final building = buildings[index];

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Colors.blue,
                            child: Icon(Icons.apartment, color: Colors.white),
                          ),
                          title: Text(
                            building.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(building.address),
                              const SizedBox(height: 4),
                              Text(
                                'Tạo lúc ${_formatDate(building.createdAt)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          trailing: isAdmin
                              ? Builder(
                                  builder: (BuildContext context) {
                                    return IconButton(
                                      icon: const Icon(Icons.more_vert),
                                      onPressed: () {
                                        // Get the position of the button
                                        final RenderBox button = context.findRenderObject() as RenderBox;
                                        final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
                                        final RelativeRect position = RelativeRect.fromRect(
                                          Rect.fromPoints(
                                            button.localToGlobal(Offset.zero, ancestor: overlay) + const Offset(0, 48),
                                            button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
                                          ),
                                          Offset.zero & overlay.size,
                                        );

                                        // Show menu at button position
                                        showMenu<String>(
                                          context: context,
                                          position: position,
                                          
                                          items: [
                                            const PopupMenuItem(
                                              value: 'rooms',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.meeting_room, size: 20),
                                                  SizedBox(width: 8),
                                                  Text('Quản lý phòng'),
                                                ],
                                              ),
                                            ),
                                            const PopupMenuItem(
                                              value: 'edit',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.edit, size: 20),
                                                  SizedBox(width: 8),
                                                  Text('Chỉnh sửa'),
                                                ],
                                              ),
                                            ),
                                            const PopupMenuItem(
                                              value: 'delete',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.delete, size: 20, color: Colors.red),
                                                  SizedBox(width: 8),
                                                  Text('Xoá', style: TextStyle(color: Colors.red)),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ).then((value) {
                                          if (value == 'edit') {
                                            _showEditBuildingDialog(building);
                                          } else if (value == 'delete') {
                                            _deleteBuilding(building);
                                          } else if (value == 'rooms') {
                                            Navigator.pushNamed(
                                              context,
                                              '/building-rooms',
                                              arguments: building,
                                            );
                                          }
                                        });
                                      },
                                    );
                                  },
                                )
                              : IconButton(
                                  icon: const Icon(Icons.arrow_forward_ios, size: 16),
                                  onPressed: () {
                                    Navigator.pushNamed(
                                      context,
                                      '/building-rooms',
                                      arguments: building,
                                    );
                                  },
                                ),
                          onTap: () {
                            Navigator.pushNamed(
                              context,
                              '/building-rooms',
                              arguments: building,
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // ========================================
  // MEMBERS TAB
  // ========================================

  Widget _buildMembersTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          /// ===== ADMIN ACTIONS =====
          FutureBuilder<Membership?>(
            future: _getMyMembership(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox();

              final membership = snapshot.data!;
              if (membership.role != 'admin') return const SizedBox();

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ElevatedButton(
                    onPressed: loadingInvite ? null : _loadInviteCode,
                    child: const Text("Get Invite Code"),
                  ),
                  if (inviteCode != null) ...[
                    const SizedBox(height: 8),
                    SelectableText(
                      "Invite Code: $inviteCode",
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                  const Divider(height: 32),
                ],
              );
            },
          ),

          /// ===== MEMBERS LIST =====
          const Text(
            "Members",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          Expanded(
            child: FutureBuilder<List<Membership>>(
              future: _getMembers(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return const Center(child: Text("No members found."));
                }

                final members = snapshot.data!;

                return ListView.builder(
                  itemCount: members.length,
                  itemBuilder: (context, index) {
                    final member = members[index];
                    
                    return FutureBuilder(
                      future: _authService.getOwnerData(member.ownerId),
                      builder: (context, ownerSnapshot) {
                        // Show loading state while fetching owner data
                        if (ownerSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: const CircleAvatar(
                                child: Icon(Icons.person),
                              ),
                              title: const Text('Loading...'),
                              subtitle: Text(member.role.toUpperCase()),
                            ),
                          );
                        }

                        // Get owner name with fallback to email or ID
                        final ownerName = ownerSnapshot.data?.name ??
                            ownerSnapshot.data?.email ??
                            member.ownerId;

                        final ownerEmail = ownerSnapshot.data?.email;

                        // Convert role to Vietnamese
                        final roleText = member.role == 'admin' ? 'Quản trị viên' : 'Thành viên';

                        // Display the member with actual name
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: member.role == 'admin'
                                  ? Colors.orange
                                  : Colors.blue,
                              child: Icon(
                                member.role == 'admin'
                                    ? Icons.admin_panel_settings
                                    : Icons.person,
                                color: Colors.white,
                              ),
                            ),
                            title: Text(
                              ownerName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  roleText,
                                  style: TextStyle(
                                    color: member.role == 'admin'
                                        ? Colors.orange
                                        : Colors.grey,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                                if (ownerEmail != null)
                                  Text(
                                    ownerEmail,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey,
                                    ),
                                  ),
                              ],
                            ),
                            // REPLACE THE TRAILING PROPERTY WITH THIS:
                            trailing: FutureBuilder<Membership?>(
                              future: _getMyMembership(),
                              builder: (context, myMembershipSnapshot) {
                                if (!myMembershipSnapshot.hasData) {
                                  return member.status == 'active'
                                      ? const Icon(
                                          Icons.check_circle,
                                          color: Colors.green,
                                          size: 20,
                                        )
                                      : const Icon(
                                          Icons.pending,
                                          color: Colors.orange,
                                          size: 20,
                                        );
                                }
                                
                                final myMembership = myMembershipSnapshot.data!;
                                
                                // Only show actions if current user is admin
                                if (myMembership.role != 'admin') {
                                  return member.status == 'active'
                                      ? const Icon(
                                          Icons.check_circle,
                                          color: Colors.green,
                                          size: 20,
                                        )
                                      : const Icon(
                                          Icons.pending,
                                          color: Colors.orange,
                                          size: 20,
                                        );
                                }
                                
                                // Don't show promote/demote for yourself
                                if (member.ownerId == myMembership.ownerId) {
                                  return const Icon(
                                    Icons.check_circle,
                                    color: Colors.green,
                                    size: 20,
                                  );
                                }
                                
                                // Show popup menu for other members
                                return Builder(
                                  builder: (BuildContext context) {
                                    return IconButton(
                                      icon: const Icon(Icons.more_vert),
                                      onPressed: () {
                                        // CAPTURE ScaffoldMessenger BEFORE async operations
                                        final scaffoldMessenger = ScaffoldMessenger.of(context);

                                        // Get the position of the button
                                        final RenderBox button = context.findRenderObject() as RenderBox;
                                        final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
                                        final RelativeRect position = RelativeRect.fromRect(
                                          Rect.fromPoints(
                                            button.localToGlobal(Offset.zero, ancestor: overlay) + const Offset(0, 48),
                                            button.localToGlobal(button.size.bottomRight(Offset.zero), ancestor: overlay),
                                          ),
                                          Offset.zero & overlay.size,
                                        );

                                        // Show menu at button position
                                        showMenu<String>(
                                          context: context,
                                          position: position,
                                          items: [
                                            if (member.role == 'member')
                                              const PopupMenuItem(
                                                value: 'promote',
                                                child: Row(
                                                  children: [
                                                    Icon(Icons.arrow_upward, size: 20),
                                                    SizedBox(width: 8),
                                                    Text('Thăng cấp Admin'),
                                                  ],
                                                ),
                                              ),
                                            if (member.role == 'admin')
                                            const PopupMenuItem(
                                              value: 'remove',
                                              child: Row(
                                                children: [
                                                  Icon(Icons.remove_circle, size: 20, color: Colors.red),
                                                  SizedBox(width: 8),
                                                  Text('Xóa khỏi tổ chức', style: TextStyle(color: Colors.red)),
                                                ],
                                              ),
                                            ), // required majority vote
                                          ],
                                        ).then((value) async {
                                          if (value == 'promote') {
                                            final success = await _orgService.promoteMemberToAdmin(
                                              currentAdminId: myMembership.ownerId,
                                              memberIdToPromote: member.ownerId,
                                              orgId: _organization.id,
                                            );
                                            if (success && mounted) {
                                              scaffoldMessenger.showSnackBar(
                                                const SnackBar(content: Text('Đã thăng cấp thành admin')),
                                              );
                                              setState(() {});
                                            }
                                          } else if (value == 'remove') {
                                            // Show confirmation dialog
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (context) => AlertDialog(
                                                title: const Text('Xác nhận xóa'),
                                                content: Text('Bạn có chắc muốn xóa $ownerName khỏi tổ chức?'),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(context, false),
                                                    child: const Text('Hủy'),
                                                  ),
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(context, true),
                                                    child: const Text('Xóa', style: TextStyle(color: Colors.red)),
                                                  ),
                                                ],
                                              ),
                                            );
                                            
                                            if (confirm == true) {
                                              final success = await _orgService.leaveOrganization(
                                                member.ownerId,
                                                _organization.id,
                                              );
                                              if (success && mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(content: Text('Đã xóa thành viên')),
                                                );
                                                setState(() {});
                                              }
                                            }
                                          }
                                        });
                                      },
                                    );
                                  },
                                );
                              },
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ========================================
  // HELPER METHODS
  // ========================================

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      return 'hôm nay';
    } else if (difference.inDays == 1) {
      return 'hôm qua';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} ngày trước';
    } else if (difference.inDays < 30) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks tuần trước';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '$months tháng trước';
    } else {
      final years = (difference.inDays / 365).floor();
      return '$years năm trước';
    }
  }
}