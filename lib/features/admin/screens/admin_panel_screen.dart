import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smartfit/core/constants/api_endpoints.dart';
import 'package:smartfit/core/constants/app_colors.dart';
import 'package:smartfit/core/providers/supabase_provider.dart';
import 'package:smartfit/core/router/app_router.dart';
import 'package:smartfit/core/widgets/clothing_pattern_background.dart';
import 'package:smartfit/features/admin/data/admin_repository.dart';

class AdminPanelScreen extends ConsumerStatefulWidget {
  const AdminPanelScreen({super.key});

  @override
  ConsumerState<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends ConsumerState<AdminPanelScreen> {
  late AdminRepository _repo;
  bool _loading = true;
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _messages = [];
  static const _suspensionDurations = <String, Duration>{
    '5 mins': Duration(minutes: 5),
    '30 mins': Duration(minutes: 30),
    '12 hours': Duration(hours: 12),
    '24 hours': Duration(hours: 24),
    '1 week': Duration(days: 7),
    '1 month': Duration(days: 30),
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    _repo = AdminRepository(ref.read(supabaseClientProvider));
    if (!_repo.isCurrentUserAdmin) {
      if (mounted) context.go(RoutePaths.home);
      return;
    }
    setState(() => _loading = true);
    try {
      final users = await _repo.fetchUsers();
      final messages = await _repo.fetchRecentMessages();
      if (!mounted) return;
      setState(() {
        _users = users;
        _messages = messages;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Admin load failed: $e')));
    }
  }

  Future<void> _logout() async {
    await _repo.signOut();
    if (mounted) context.go(RoutePaths.login);
  }

  bool _isFlagged(Map<String, dynamic> message) {
    final metadata = message['metadata'];
    if (metadata is Map && metadata['moderation'] is Map) {
      return metadata['moderation']['flagged'] == true &&
          metadata['moderation']['review_status'] != 'reviewed';
    }
    final text = (message['content'] ?? '').toString().toLowerCase();
    return [
      '18+',
      'nude',
      'porn',
      'sex',
      'suicide',
      'kill',
      'bomb',
      'abuse',
    ].any(text.contains);
  }

  String _displayName(Map<String, dynamic> user) =>
      (user['full_name'] ?? user['username'] ?? 'Unnamed user').toString();

  Map<String, dynamic>? _profileForMessage(Map<String, dynamic> message) {
    final session = message['chat_sessions'];
    if (session is! Map) return null;
    final profile = session['profiles'];
    return profile is Map ? Map<String, dynamic>.from(profile) : null;
  }

  Map<String, dynamic>? _sessionForMessage(Map<String, dynamic> message) {
    final session = message['chat_sessions'];
    return session is Map ? Map<String, dynamic>.from(session) : null;
  }

  String _identityLine(Map<String, dynamic> user) => [
    if (user['username'] != null && user['username'].toString().isNotEmpty)
      '@${user['username']}',
    if (user['email'] != null && user['email'].toString().isNotEmpty)
      user['email'],
  ].join('  •  ');

  bool _isSuspended(Map<String, dynamic> user) {
    final raw = user['suspended_until'];
    if (raw == null) return false;
    final until = DateTime.tryParse(raw.toString());
    return until != null && until.isAfter(DateTime.now().toUtc());
  }

  String _suspensionLine(Map<String, dynamic> user) {
    final until = DateTime.tryParse((user['suspended_until'] ?? '').toString());
    if (until == null) return '';
    return 'Suspended until ${until.toLocal()}';
  }

  Future<void> _toggleBan(Map<String, dynamic> user) async {
    final banned = user['is_banned'] == true;
    final reasonCtrl = TextEditingController(
      text: user['ban_reason'] as String?,
    );
    final reason = banned
        ? ''
        : await showDialog<String>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: Text('Ban ${_displayName(user)}'),
              content: TextField(
                controller: reasonCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText: 'Reason shown in admin records',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, reasonCtrl.text),
                  child: const Text('Ban user'),
                ),
              ],
            ),
          );
    if (!banned && reason == null) return;
    await _repo.setBan(
      userId: user['id'] as String,
      banned: !banned,
      reason: reason,
    );
    await _load();
  }

  Future<void> _suspendUser(Map<String, dynamic> user) async {
    String selected = _suspensionDurations.keys.first;
    final reasonCtrl = TextEditingController(
      text: user['suspension_reason'] as String?,
    );
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Suspend ${_displayName(user)}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selected,
                decoration: const InputDecoration(labelText: 'Duration'),
                items: _suspensionDurations.keys
                    .map(
                      (label) =>
                          DropdownMenuItem(value: label, child: Text(label)),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setDialogState(() => selected = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  hintText:
                      'Warning reason. User will be told another violation may cause permanent ban.',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, selected),
              child: const Text('Suspend'),
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await _repo.suspendUser(
      userId: user['id'] as String,
      duration: _suspensionDurations[result]!,
      reason: reasonCtrl.text,
    );
    await _load();
  }

  Future<void> _clearSuspension(Map<String, dynamic> user) async {
    await _repo.clearSuspension(user['id'] as String);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final flagged = _messages.where(_isFlagged).length;
    final banned = _users.where((u) => u['is_banned'] == true).length;
    final suspended = _users.where(_isSuspended).length;

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.primary,
          elevation: 0,
          title: const Text('Admin Panel'),
          actions: [
            IconButton(
              tooltip: 'Refresh',
              onPressed: _load,
              icon: const Icon(Icons.refresh),
            ),
            IconButton(
              tooltip: 'Logout',
              onPressed: _logout,
              icon: const Icon(Icons.logout),
            ),
          ],
          bottom: const TabBar(
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.outline,
            indicatorColor: AppColors.primary,
            tabs: [
              Tab(icon: Icon(Icons.dashboard_outlined), text: 'Overview'),
              Tab(icon: Icon(Icons.people_alt_outlined), text: 'Users'),
              Tab(icon: Icon(Icons.shield_outlined), text: 'Chats'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : Stack(
                children: [
                  const Positioned.fill(
                    child: ClothingPatternBackground(
                      opacity: 0.05,
                      color: Color(0xFFFF2E93),
                    ),
                  ),
                  TabBarView(
                    children: [
                      _overviewTab(flagged, banned, suspended),
                      _usersTab(),
                      _chatsTab(),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  Widget _overviewTab(int flagged, int banned, int suspended) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _adminHeader(),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _stat('Total users', _users.length.toString(), Icons.people_alt),
            _stat('Banned', banned.toString(), Icons.block),
            _stat('Suspended', suspended.toString(), Icons.timer_off_outlined),
            _stat('Needs review', flagged.toString(), Icons.report),
            _stat('Messages', _messages.length.toString(), Icons.chat),
          ],
        ),
        const SizedBox(height: 22),
        _panel(
          title: 'Safety workflow',
          child: Column(
            children: const [
              _FlowRow('1', 'Review flagged chats by user identity.'),
              _FlowRow(
                '2',
                'Suspend users first, then ban repeated violations.',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _usersTab() {
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: _users.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, index) => _userTile(_users[index]),
    );
  }

  Widget _chatsTab() {
    final sorted = [..._messages]
      ..sort((a, b) {
        final af = _isFlagged(a) ? 0 : 1;
        final bf = _isFlagged(b) ? 0 : 1;
        final flagCompare = af.compareTo(bf);
        if (flagCompare != 0) return flagCompare;
        final ad = DateTime.tryParse((a['created_at'] ?? '').toString());
        final bd = DateTime.tryParse((b['created_at'] ?? '').toString());
        return (bd ?? DateTime.fromMillisecondsSinceEpoch(0)).compareTo(
          ad ?? DateTime.fromMillisecondsSinceEpoch(0),
        );
      });
    return ListView.separated(
      padding: const EdgeInsets.all(20),
      itemCount: sorted.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, index) => _messageTile(sorted[index]),
    );
  }

  Widget _adminHeader() {
    return _panel(
      title: 'Control center',
      child: Row(
        children: [
          const CircleAvatar(
            backgroundColor: AppColors.primary,
            child: Icon(Icons.admin_panel_settings, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              ApiEndpoints.adminEmail,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon) {
    return Container(
      width: 156,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
          ),
          Text(label, style: const TextStyle(color: AppColors.outline)),
        ],
      ),
    );
  }

  Widget _userTile(Map<String, dynamic> user) {
    final banned = user['is_banned'] == true;
    final suspended = _isSuspended(user);
    return _panel(
      title: _displayName(user),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _identityLine(user).isEmpty
                ? 'No email saved'
                : _identityLine(user),
          ),
          if (banned && user['ban_reason'] != null) ...[
            const SizedBox(height: 8),
            Text(
              'Banned: ${user['ban_reason']}',
              style: const TextStyle(color: AppColors.error),
            ),
          ],
          if (suspended) ...[
            const SizedBox(height: 8),
            Text(
              _suspensionLine(user),
              style: const TextStyle(color: AppColors.error),
            ),
            if (user['suspension_reason'] != null)
              Text(
                'Reason: ${user['suspension_reason']}',
                style: const TextStyle(color: AppColors.outline),
              ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: banned ? AppColors.primary : AppColors.error,
                ),
                onPressed: () => _toggleBan(user),
                icon: Icon(banned ? Icons.lock_open : Icons.block),
                label: Text(banned ? 'Unban' : 'Ban'),
              ),
              OutlinedButton.icon(
                onPressed: banned ? null : () => _suspendUser(user),
                icon: const Icon(Icons.timer_off_outlined),
                label: const Text('Suspend'),
              ),
              if (suspended)
                TextButton.icon(
                  onPressed: () => _clearSuspension(user),
                  icon: const Icon(Icons.lock_open),
                  label: const Text('Clear suspension'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _messageTile(Map<String, dynamic> message) {
    final flagged = _isFlagged(message);
    final session = _sessionForMessage(message);
    final profile = _profileForMessage(message);
    final userName = profile == null ? 'Unknown user' : _displayName(profile);
    final identity = profile == null ? '' : _identityLine(profile);
    final userId = (session?['user_id'] ?? '').toString();
    final createdAt = DateTime.tryParse(
      (message['created_at'] ?? '').toString(),
    );
    final metadata = message['metadata'];
    final sourceBrands = metadata is Map ? metadata['brands_searched'] : null;
    final products = metadata is Map ? metadata['products'] : null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: flagged ? const Color(0xFFFFF1F2) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: flagged
              ? AppColors.error.withValues(alpha: 0.35)
              : AppColors.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                flagged ? Icons.report : Icons.chat_bubble_outline,
                color: flagged ? AppColors.error : AppColors.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  userName,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(message['role'].toString().toUpperCase()),
            ],
          ),
          if (identity.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(identity, style: const TextStyle(color: AppColors.outline)),
          ],
          if (userId.isNotEmpty) ...[
            const SizedBox(height: 4),
            SelectableText(
              'User ID: $userId',
              style: const TextStyle(color: AppColors.outline, fontSize: 12),
            ),
          ],
          if (createdAt != null) ...[
            const SizedBox(height: 4),
            Text(
              createdAt.toLocal().toString(),
              style: const TextStyle(color: AppColors.outline, fontSize: 12),
            ),
          ],
          const SizedBox(height: 10),
          Text(message['content'].toString()),
          if (sourceBrands is List && sourceBrands.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Scraped sources: ${sourceBrands.join(", ")}',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ],
          if (products is List && products.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...products.take(5).map((item) {
              if (item is! Map) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SelectableText(
                  '${item['brand'] ?? 'Store'}: ${item['product_url'] ?? ''}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.outline,
                  ),
                ),
              );
            }),
          ],
          if (flagged) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () async {
                    await _repo.markMessageReviewed(message['id'] as String);
                    await _load();
                  },
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Mark reviewed'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FlowRow extends StatelessWidget {
  final String number;
  final String text;

  const _FlowRow(this.number, this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: AppColors.primary.withValues(alpha: 0.12),
            child: Text(
              number,
              style: const TextStyle(color: AppColors.primary),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
