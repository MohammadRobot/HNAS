import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../models.dart';
import '../providers.dart';
import '../services/api_client.dart';

class UsersManagementScreen extends ConsumerStatefulWidget {
  const UsersManagementScreen({super.key});

  @override
  ConsumerState<UsersManagementScreen> createState() =>
      _UsersManagementScreenState();
}

class _UsersManagementScreenState extends ConsumerState<UsersManagementScreen> {
  static const List<String> _roleFilterOptions = <String>[
    'all',
    'admin',
    'supervisor',
    'nurse',
  ];

  final TextEditingController _agencyFilterController = TextEditingController();

  bool _isLoading = false;
  String? _errorMessage;
  String _roleFilter = 'all';
  bool _seededAgencyFilter = false;
  List<ManagedUserModel> _users = const <ManagedUserModel>[];

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_loadUsers);
  }

  @override
  void dispose() {
    _agencyFilterController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final profile = await ref.read(userProfileProvider.future);
      if (!mounted) {
        return;
      }

      if (profile == null) {
        setState(() {
          _users = const <ManagedUserModel>[];
          _errorMessage = 'User profile was not found.';
        });
        return;
      }

      final canManageUsers =
          profile.role == 'admin' || profile.role == 'supervisor';
      if (!canManageUsers) {
        setState(() {
          _users = const <ManagedUserModel>[];
          _errorMessage =
              'Only admin and supervisor roles can manage staff users.';
        });
        return;
      }

      if (!_seededAgencyFilter &&
          profile.role == 'admin' &&
          (profile.agencyId ?? '').trim().isNotEmpty) {
        _agencyFilterController.text = profile.agencyId!.trim();
        _seededAgencyFilter = true;
      }

      final api = ref.read(apiClientProvider);
      final role = _roleFilter == 'all' ? null : _roleFilter;
      final agencyId = _resolveAgencyFilter(profile);
      final users = await api.listUsers(
        role: role,
        agencyId: agencyId,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _users = users;
        _errorMessage = null;
      });
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.message;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = '$error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String? _resolveAgencyFilter(AppUserProfile profile) {
    if (profile.role == 'supervisor') {
      return profile.agencyId;
    }

    final agencyId = _agencyFilterController.text.trim();
    if (agencyId.isNotEmpty) {
      return agencyId;
    }

    final fallbackAgencyId = (profile.agencyId ?? '').trim();
    return fallbackAgencyId.isEmpty ? null : fallbackAgencyId;
  }

  Future<void> _openCreateDialog(AppUserProfile profile) async {
    final result = await showDialog<_UserFormResult>(
      context: context,
      builder: (dialogContext) => _UserFormDialog.create(
        actorProfile: profile,
        initialAgencyId: _resolveAgencyFilter(profile),
      ),
    );

    if (result == null) {
      return;
    }

    try {
      await ref.read(apiClientProvider).createUser(
            email: result.email,
            password: result.password ?? '',
            displayName: result.displayName,
            role: result.role,
            agencyId: result.agencyId,
            disabled: result.disabled,
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User created successfully.')),
      );
      await _loadUsers();
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to create user: ${error.message}')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to create user: $error')),
      );
    }
  }

  Future<void> _openEditDialog(
    AppUserProfile profile,
    ManagedUserModel user,
  ) async {
    final result = await showDialog<_UserFormResult>(
      context: context,
      builder: (dialogContext) => _UserFormDialog.edit(
        actorProfile: profile,
        user: user,
        isEditingSelf: profile.uid == user.uid,
      ),
    );

    if (result == null) {
      return;
    }

    final changedEmail = result.email.toLowerCase();
    final existingEmail = user.email.toLowerCase();

    final changedDisplayName = result.displayName;
    final changedRole = result.role;
    final changedAgencyId = result.agencyId.trim();

    final hasEmailChange = changedEmail != existingEmail;
    final hasNameChange = changedDisplayName != user.displayName;
    final hasRoleChange = changedRole != user.role;
    final hasAgencyChange = changedAgencyId != user.agencyId;
    final hasDisabledChange = result.disabled != user.disabled;
    final hasPasswordChange = (result.password ?? '').isNotEmpty;

    if (!hasEmailChange &&
        !hasNameChange &&
        !hasRoleChange &&
        !hasAgencyChange &&
        !hasDisabledChange &&
        !hasPasswordChange) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No changes to save.')),
      );
      return;
    }

    try {
      await ref.read(apiClientProvider).updateUser(
            uid: user.uid,
            email: hasEmailChange ? result.email : null,
            displayName: hasNameChange ? result.displayName : null,
            role: hasRoleChange ? result.role : null,
            agencyId: hasAgencyChange ? changedAgencyId : null,
            disabled: hasDisabledChange ? result.disabled : null,
            password: hasPasswordChange ? result.password : null,
          );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User updated successfully.')),
      );
      await _loadUsers();
    } on ApiException catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to update user: ${error.message}')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Unable to update user: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(userProfileProvider);

    return profileAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => Scaffold(
        appBar: AppBar(title: const Text('Users Management')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Unable to load user profile: $error'),
          ),
        ),
      ),
      data: (profile) {
        if (profile == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Users Management')),
            body: const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text('No user profile found for current account.'),
              ),
            ),
          );
        }

        final canManageUsers =
            profile.role == 'admin' || profile.role == 'supervisor';

        return Scaffold(
          appBar: AppBar(
            title: const Text('Users Management'),
            actions: <Widget>[
              if (canManageUsers)
                IconButton(
                  tooltip: 'Add user',
                  onPressed: () => _openCreateDialog(profile),
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                ),
              IconButton(
                tooltip: 'Refresh',
                onPressed: _loadUsers,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            children: <Widget>[
              _UsersHero(
                actorRole: profile.role,
                totalUsers: _users.length,
                disabledUsers: _users.where((user) => user.disabled).length,
                canManageUsers: canManageUsers,
                onCreateUser:
                    canManageUsers ? () => _openCreateDialog(profile) : null,
              ),
              const SizedBox(height: 12),
              if (canManageUsers)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        SizedBox(
                          width: 180,
                          child: DropdownButtonFormField<String>(
                            initialValue: _roleFilter,
                            decoration: const InputDecoration(
                              labelText: 'Role filter',
                            ),
                            items: _roleFilterOptions
                                .map(
                                  (role) => DropdownMenuItem<String>(
                                    value: role,
                                    child: Text(
                                      role == 'all'
                                          ? 'All roles'
                                          : _toTitle(role),
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              if (value == null) {
                                return;
                              }
                              setState(() {
                                _roleFilter = value;
                              });
                              _loadUsers();
                            },
                          ),
                        ),
                        if (profile.role == 'admin')
                          SizedBox(
                            width: 240,
                            child: TextFormField(
                              controller: _agencyFilterController,
                              decoration: const InputDecoration(
                                labelText: 'Agency ID',
                                hintText: 'agency_demo_1',
                              ),
                            ),
                          ),
                        if (profile.role == 'admin')
                          OutlinedButton.icon(
                            onPressed: _loadUsers,
                            icon: const Icon(Icons.search_rounded),
                            label: const Text('Apply filters'),
                          ),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 12),
              if (!canManageUsers)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Only admin and supervisor roles can manage staff users.',
                    ),
                  ),
                )
              else if (_isLoading)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (_errorMessage != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Unable to load users: $_errorMessage',
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _loadUsers,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_users.isEmpty)
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No users found for the selected filters.'),
                  ),
                )
              else
                Card(
                  child: Column(
                    children: _users
                        .map(
                          (user) => _UserTile(
                            user: user,
                            canManage: canManageUsers,
                            onEdit: () => _openEditDialog(profile, user),
                          ),
                        )
                        .toList(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _UsersHero extends StatelessWidget {
  const _UsersHero({
    required this.actorRole,
    required this.totalUsers,
    required this.disabledUsers,
    required this.canManageUsers,
    this.onCreateUser,
  });

  final String actorRole;
  final int totalUsers;
  final int disabledUsers;
  final bool canManageUsers;
  final VoidCallback? onCreateUser;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabledUsers = totalUsers - disabledUsers;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[colorScheme.primary, colorScheme.secondary],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Staff Accounts',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: colorScheme.onPrimary,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            'Role: ${_toTitle(actorRole)} • Enabled: $enabledUsers • Disabled: $disabledUsers',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onPrimary.withValues(alpha: 0.9),
                ),
          ),
          if (canManageUsers) ...<Widget>[
            const SizedBox(height: 14),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.onPrimary,
                foregroundColor: colorScheme.primary,
              ),
              onPressed: onCreateUser,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text('Create Staff User'),
            ),
          ],
        ],
      ),
    );
  }
}

class _UserTile extends StatelessWidget {
  const _UserTile({
    required this.user,
    required this.canManage,
    required this.onEdit,
  });

  final ManagedUserModel user;
  final bool canManage;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final lastSignIn = _formatDateTime(user.lastSignInAt);
    final title = user.displayName.isNotEmpty ? user.displayName : user.email;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      leading: CircleAvatar(
        backgroundColor: user.disabled
            ? Colors.grey.shade300
            : Theme.of(context).colorScheme.primaryContainer,
        child: Text(title.isEmpty ? '?' : title[0].toUpperCase()),
      ),
      title: Text(title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(user.email),
          Text(
            'Role: ${user.roleLabel} • Agency: ${user.agencyId.isEmpty ? 'N/A' : user.agencyId}',
          ),
          Text('Last sign in: ${lastSignIn ?? 'Never'}'),
        ],
      ),
      trailing: canManage
          ? IconButton(
              tooltip: 'Edit user',
              onPressed: onEdit,
              icon: Icon(
                user.disabled
                    ? Icons.lock_person_outlined
                    : Icons.edit_outlined,
              ),
            )
          : null,
    );
  }
}

class _UserFormDialog extends StatefulWidget {
  const _UserFormDialog._({
    required this.actorProfile,
    required this.isCreate,
    this.user,
    this.initialAgencyId,
    this.isEditingSelf = false,
  });

  factory _UserFormDialog.create({
    required AppUserProfile actorProfile,
    String? initialAgencyId,
  }) {
    return _UserFormDialog._(
      actorProfile: actorProfile,
      isCreate: true,
      initialAgencyId: initialAgencyId,
    );
  }

  factory _UserFormDialog.edit({
    required AppUserProfile actorProfile,
    required ManagedUserModel user,
    required bool isEditingSelf,
  }) {
    return _UserFormDialog._(
      actorProfile: actorProfile,
      isCreate: false,
      user: user,
      isEditingSelf: isEditingSelf,
    );
  }

  final AppUserProfile actorProfile;
  final bool isCreate;
  final ManagedUserModel? user;
  final String? initialAgencyId;
  final bool isEditingSelf;

  @override
  State<_UserFormDialog> createState() => _UserFormDialogState();
}

class _UserFormDialogState extends State<_UserFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayNameController;
  late final TextEditingController _emailController;
  late final TextEditingController _passwordController;
  late final TextEditingController _agencyIdController;
  late String _role;
  late bool _disabled;

  late final List<String> _roleOptions;

  bool get _canEditAgencyId => widget.actorProfile.role == 'admin';

  bool get _canEditRole {
    if (widget.isEditingSelf) {
      return false;
    }
    return widget.actorProfile.role == 'admin';
  }

  @override
  void initState() {
    super.initState();
    final user = widget.user;

    _displayNameController = TextEditingController(
      text: user?.displayName ?? '',
    );
    _emailController = TextEditingController(
      text: user?.email ?? '',
    );
    _passwordController = TextEditingController();
    _agencyIdController = TextEditingController(
      text: user?.agencyId ??
          widget.initialAgencyId ??
          widget.actorProfile.agencyId ??
          '',
    );

    final baseRoleOptions = widget.actorProfile.role == 'admin'
        ? <String>['admin', 'supervisor', 'nurse']
        : <String>['nurse'];
    if (user != null && !baseRoleOptions.contains(user.role)) {
      baseRoleOptions.insert(0, user.role);
    }
    _roleOptions = baseRoleOptions;

    _role = user?.role ?? _roleOptions.first;
    if (!_roleOptions.contains(_role)) {
      _role = _roleOptions.first;
    }

    _disabled = user?.disabled ?? false;
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _agencyIdController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final password = _passwordController.text;
    final normalizedPassword = password.trim().isEmpty ? null : password;

    Navigator.of(context).pop(
      _UserFormResult(
        displayName: _displayNameController.text.trim(),
        email: _emailController.text.trim(),
        role: _role,
        agencyId: _agencyIdController.text.trim(),
        password: normalizedPassword,
        disabled: _disabled,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = widget.isCreate ? 'Create User' : 'Edit User';

    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 520,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextFormField(
                  controller: _displayNameController,
                  decoration: const InputDecoration(
                    labelText: 'Display Name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Display name is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.alternate_email_outlined),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    final email = (value ?? '').trim();
                    if (email.isEmpty) {
                      return 'Email is required.';
                    }
                    if (!email.contains('@') || !email.contains('.')) {
                      return 'Enter a valid email address.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  items: _roleOptions
                      .map(
                        (role) => DropdownMenuItem<String>(
                          value: role,
                          child: Text(_toTitle(role)),
                        ),
                      )
                      .toList(),
                  onChanged: _canEditRole
                      ? (value) {
                          if (value == null) {
                            return;
                          }
                          setState(() {
                            _role = value;
                          });
                        }
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _agencyIdController,
                  enabled: _canEditAgencyId,
                  decoration: const InputDecoration(
                    labelText: 'Agency ID',
                    prefixIcon: Icon(Icons.business_outlined),
                  ),
                  validator: (value) {
                    final agencyId = (value ?? '').trim();
                    if (agencyId.isEmpty) {
                      return 'Agency ID is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: widget.isCreate
                        ? 'Temporary Password'
                        : 'New Password (optional)',
                    prefixIcon: const Icon(Icons.password_outlined),
                  ),
                  obscureText: true,
                  validator: (value) {
                    final raw = (value ?? '').trim();
                    if (widget.isCreate && raw.isEmpty) {
                      return 'Password is required for new users.';
                    }
                    if (raw.isNotEmpty && raw.length < 8) {
                      return 'Use at least 8 characters.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _disabled,
                  onChanged: widget.isEditingSelf
                      ? null
                      : (value) {
                          setState(() {
                            _disabled = value;
                          });
                        },
                  title: const Text('Disable account'),
                  subtitle: const Text(
                    'Disabled users cannot sign in.',
                  ),
                ),
                if (widget.isEditingSelf)
                  const Text(
                    'Role and disable state for your own account are locked in this form.',
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(widget.isCreate ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}

class _UserFormResult {
  const _UserFormResult({
    required this.displayName,
    required this.email,
    required this.role,
    required this.agencyId,
    required this.disabled,
    this.password,
  });

  final String displayName;
  final String email;
  final String role;
  final String agencyId;
  final bool disabled;
  final String? password;
}

String _toTitle(String value) {
  if (value.isEmpty) {
    return value;
  }
  return '${value[0].toUpperCase()}${value.substring(1)}';
}

String? _formatDateTime(String? value) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }

  final parsed = DateTime.tryParse(value);
  if (parsed == null) {
    return value;
  }

  return DateFormat('yyyy-MM-dd HH:mm').format(parsed.toLocal());
}
