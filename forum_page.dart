// lib/forum_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

class ForumPage extends StatefulWidget {
  const ForumPage({super.key});

  @override
  State<ForumPage> createState() => _ForumPageState();
}

class _ForumPageState extends State<ForumPage> {
  // Firestore / Auth
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Controllers
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  // Filters
  String searchKeyword = '';
  String selectedTag = 'All';
  DateTime? selectedDate;

  // Current user info (loaded from FirebaseAuth + users collection)
  String? _currentUid;
  String? _currentUserName;
  String? _currentUserRole; // 'student' or 'teacher' or null while loading
  bool _isLoadingUser = true;

  // Tags list
  final List<String> tags = [
    'All',
    'Java',
    'OOP',
    'Algorithm',
    'Programming',
    'Assignment',
    'General'
  ];

  @override
  void initState() {
    super.initState();
    _initCurrentUser();
  }

  Future<void> _initCurrentUser() async {
    setState(() => _isLoadingUser = true);

    final user = _auth.currentUser;
    if (user == null) {
      setState(() {
        _currentUid = null;
        _currentUserName = 'Anonymous';
        _currentUserRole = 'student';
        _isLoadingUser = false;
      });
      return;
    }

    // set uid & name immediately
    setState(() {
      _currentUid = user.uid;
      _currentUserName = user.displayName ?? user.email ?? user.uid;
    });

    try {
      final doc = await _db.collection('users').doc(_currentUid).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final loadedRole = (data['role'] ?? 'student').toString().toLowerCase();
        setState(() {
          _currentUserRole = loadedRole;
          _isLoadingUser = false;
        });
      } else {
        setState(() {
          _currentUserRole = 'student';
          _isLoadingUser = false;
        });
      }
    } catch (e) {
      // fallback to student role if anything fails
      setState(() {
        _currentUserRole = 'student';
        _isLoadingUser = false;
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _showToast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  /// Helper to convert Firestore Timestamp or DateTime to DateTime
  DateTime? _toDateTime(dynamic ts) {
    if (ts == null) return null;
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime) return ts;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingUser) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('💬 Forum Discussion'),
        actions: [
          IconButton(
            tooltip: 'Filter topics',
            icon: const Icon(Icons.filter_list),
            onPressed: _openFilterOptions,
          ),
          IconButton(
            tooltip: 'Create new topic',
            icon: const Icon(Icons.add_comment_rounded),
            onPressed: _showCreateTopicDialog,
          ),
          IconButton(
            tooltip: 'FAQ & Help',
            icon: const Icon(Icons.help_outline),
            onPressed: _showHelpDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search forum topics...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                filled: true,
                fillColor: Colors.grey[100],
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Clear search',
                  onPressed: () {
                    _searchController.clear();
                    setState(() => searchKeyword = '');
                  },
                ),
              ),
              onChanged: (v) => setState(() => searchKeyword = v.trim().toLowerCase()),
            ),
          ),

          // Topics list (safe mapping + local filtering & sorting)
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              // IMPORTANT: order by createdAt (client timestamp) so ordering won't break when serverTimestamp is null
              stream: _db.collection('forumTopics').orderBy('createdAt', descending: true).snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(child: Text('Ralat memuat topik: ${snap.error}'));
                }
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());

                // Convert docs -> safe maps
                final docs = snap.data!.docs.map((d) {
                  final m = (d.data() as Map<String, dynamic>?) ?? {};
                  final createdAt = _toDateTime(m['createdAt']);
                  final serverTs = _toDateTime(m['serverTs']);
                  // prefer serverTs when available, else createdAt
                  final timestamp = serverTs ?? createdAt;
                  return {
                    'id': d.id,
                    'title': (m['title'] ?? '').toString(),
                    'description': (m['description'] ?? '').toString(),
                    'tag': (m['tag'] ?? 'General').toString(),
                    'pinned': m['pinned'] == true,
                    'edited': m['edited'] == true,
                    'editedAt': _toDateTime(m['editedAt']),
                    'timestamp': timestamp,
                    'creatorId': (m['creatorId'] ?? '').toString(),
                    'creatorName': (m['creatorName'] ?? '').toString(),
                  };
                }).toList();

                // Local filter by search/tag/date
                final filtered = docs.where((m) {
                  final title = (m['title'] as String).toLowerCase();
                  final desc = (m['description'] as String).toLowerCase();
                  final tag = (m['tag'] as String);
                  final ts = m['timestamp'] as DateTime?;
                  final searchMatch = title.contains(searchKeyword) || desc.contains(searchKeyword);
                  final tagMatch = selectedTag == 'All' ? true : (tag.toLowerCase() == selectedTag.toLowerCase());
                  bool dateMatch = true;
                  if (selectedDate != null) {
                    if (ts == null) dateMatch = false;
                    else dateMatch = _isSameDay(ts, selectedDate!);
                  }
                  return searchMatch && tagMatch && dateMatch;
                }).toList();

                // Sort: pinned first, then by timestamp desc (null-safe)
                filtered.sort((a, b) {
                  final aPinned = a['pinned'] as bool;
                  final bPinned = b['pinned'] as bool;
                  if (aPinned && !bPinned) return -1;
                  if (!aPinned && bPinned) return 1;
                  final aTs = a['timestamp'] as DateTime?;
                  final bTs = b['timestamp'] as DateTime?;
                  if (aTs == null && bTs == null) return 0;
                  if (aTs == null) return 1;
                  if (bTs == null) return -1;
                  return bTs.compareTo(aTs);
                });

                if (filtered.isEmpty) return const Center(child: Text('Tiada topik ditemui.'));

                return ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, i) => _buildPostCardFromMap(filtered[i]),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPostCardFromMap(Map<String, dynamic> m) {
    final id = m['id'] as String;
    final title = m['title'] as String;
    final description = m['description'] as String;
    final tag = m['tag'] as String;
    final pinned = m['pinned'] as bool;
    final edited = m['edited'] as bool;
    final timestamp = m['timestamp'] as DateTime?;
    final creatorId = m['creatorId'] as String;
    final creatorName = (m['creatorName'] as String).isNotEmpty ? m['creatorName'] as String : 'Anonymous';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: pinned ? Colors.yellow[50] : null,
      child: ListTile(
        title: Row(
          children: [
            Expanded(child: Text(title)),
            if (pinned)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.orange, borderRadius: BorderRadius.circular(6)),
                child: const Text('PIN', style: TextStyle(color: Colors.white, fontSize: 12)),
              ),
            if (edited)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.blueGrey, borderRadius: BorderRadius.circular(6)),
                child: const Text('Edited', style: TextStyle(color: Colors.white, fontSize: 10)),
              ),
          ],
        ),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(description, maxLines: 2, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 6),
          Row(children: [
            Chip(label: Text(tag)),
            const SizedBox(width: 8),
            Text('By $creatorName'),
            const SizedBox(width: 8),
            if (timestamp != null)
              Text('· ${DateFormat('dd/MM/yyyy').format(timestamp)}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ]),
        ]),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Tooltip(message: 'Buka topik', child: IconButton(icon: const Icon(Icons.open_in_new, size: 22), onPressed: () => _openPostDetailsById(id))),
          // Edit/Delete only for owner or teacher
          if (_currentUid != null && (_currentUid == creatorId || _currentUserRole == 'teacher')) ...[
            Tooltip(message: 'Edit topik', child: IconButton(icon: const Icon(Icons.edit, size: 22, color: Colors.blue), onPressed: () => _editTopicById(id))),
            Tooltip(message: 'Padam topik', child: IconButton(icon: const Icon(Icons.delete_forever, size: 22, color: Colors.red), onPressed: () => _tryDeleteTopicById(id))),
          ],
          // Pin only for teacher
          if (_currentUserRole == 'teacher')
            Tooltip(
              message: pinned ? 'Unpin topik' : 'Pin topik',
              child: IconButton(icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined, color: Colors.orange), onPressed: () => _togglePinById(id, pinned)),
            ),
          const SizedBox(width: 6),
          const Icon(Icons.arrow_forward_ios_rounded, size: 16),
        ]),
        onTap: () => _openPostDetailsById(id),
      ),
    );
  }

  // Create dialog
  void _showCreateTopicDialog() {
    String selectedCreateTag = tags.length > 1 ? tags[1] : 'General';
    _titleController.clear();
    _descController.clear();

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Create New Discussion'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: _titleController, decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: 8),
            TextField(controller: _descController, maxLines: 4, decoration: const InputDecoration(labelText: 'Description')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: selectedCreateTag,
              items: tags.where((t) => t != 'All').map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (v) => selectedCreateTag = v ?? selectedCreateTag,
              decoration: const InputDecoration(labelText: 'Tag'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final title = _titleController.text.trim();
              final desc = _descController.text.trim();
              if (title.isEmpty || desc.isEmpty) return;

              final creatorId = _currentUid ?? '';
              final creatorName = _currentUserName ?? '';

              // ensure non-null client-side createdAt so ordering works immediately
              final clientCreatedAt = DateTime.now();

              final docRef = await _db.collection('forumTopics').add({
                'title': title,
                'description': desc,
                'tag': selectedCreateTag,
                'creatorId': creatorId,
                'creatorName': creatorName,
                'createdAt': clientCreatedAt,
                'serverTs': FieldValue.serverTimestamp(), // canonical time
                'edited': false,
                'pinned': false,
              });

              // simple broadcast notification doc (optional)
              await _db.collection('notifications').add({
                'title': 'New forum topic',
                'message': title,
                'topicId': docRef.id,
                'broadcast': true,
                'timestamp': FieldValue.serverTimestamp(),
              });

              _titleController.clear();
              _descController.clear();
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  // Edit helpers
  Future<void> _editTopicById(String docId) async {
    final doc = await _db.collection('forumTopics').doc(docId).get();
    if (!doc.exists) return;
    final data = doc.data() ?? {};
    _titleController.text = (data['title'] ?? '').toString();
    _descController.text = (data['description'] ?? '').toString();
    String tag = (data['tag'] ?? (tags.length > 1 ? tags[1] : 'General')).toString();

    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit Topic'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: _titleController, decoration: const InputDecoration(labelText: 'Title')),
            const SizedBox(height: 8),
            TextField(controller: _descController, maxLines: 4, decoration: const InputDecoration(labelText: 'Description')),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: tag,
              items: tags.where((t) => t != 'All').map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
              onChanged: (v) => tag = v ?? tag,
              decoration: const InputDecoration(labelText: 'Tag'),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final newTitle = _titleController.text.trim();
              final newDesc = _descController.text.trim();
              if (newTitle.isEmpty || newDesc.isEmpty) return;
              await _db.collection('forumTopics').doc(docId).update({
                'title': newTitle,
                'description': newDesc,
                'tag': tag,
                'edited': true,
                'editedAt': FieldValue.serverTimestamp(),
              });

              // optional notification
              await _db.collection('notifications').add({
                'title': 'Topik dikemaskini',
                'message': newTitle,
                'topicId': docId,
                'broadcast': true,
                'timestamp': FieldValue.serverTimestamp(),
              });

              if (mounted) Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // Delete helpers - deletes comments batch too
  Future<void> _tryDeleteTopicById(String docId) async {
    final doc = await _db.collection('forumTopics').doc(docId).get();
    if (!doc.exists) return;
    final data = doc.data() ?? {};
    final ownerId = (data['creatorId'] ?? '').toString();
    if (_currentUid == null || (_currentUid != ownerId && _currentUserRole != 'teacher')) {
      _showToast('Anda tidak dibenarkan memadam topik ini.');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: const Text('Adakah anda pasti mahu memadam topik ini?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );

    if (confirm == true) {
      // delete comments then topic using batch
      final commentsSnap = await _db.collection('forumTopics').doc(docId).collection('comments').get();
      final batch = _db.batch();
      for (final c in commentsSnap.docs) {
        batch.delete(c.reference);
      }
      batch.delete(_db.collection('forumTopics').doc(docId));
      await batch.commit();
      _showToast('Topik dipadamkan.');
    }
  }

  // Pin helpers
  Future<void> _togglePinById(String docId, bool currentlyPinned) async {
    if (_currentUserRole != 'teacher') {
      _showToast('Hanya teacher boleh pin/unpin topik.');
      return;
    }
    await _db.collection('forumTopics').doc(docId).update({'pinned': !currentlyPinned});
    _showToast(currentlyPinned ? 'Topik unpinned.' : 'Topik pinned.');
  }

  // Open detail
  void _openPostDetailsById(String docId) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ForumDetailPage(topicId: docId)));
  }

  // Filter dialog
  void _openFilterOptions() {
    String tempTag = selectedTag;
    DateTime? tempDate = selectedDate;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Filter Topics'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            value: tempTag,
            decoration: const InputDecoration(labelText: 'Filter by Tag'),
            items: tags.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
            onChanged: (v) => tempTag = v ?? 'All',
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            child: Text(
  tempDate == null
      ? 'Filter by Date'
      : 'Selected: ${DateFormat('dd/MM/yyyy').format(tempDate!)}',
),

            onPressed: () async {
              final picked = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2030));
              if (picked != null) {
                setState(() => tempDate = picked);
              }
            },
          )
        ]),
        actions: [
          TextButton(onPressed: () {
            setState(() {
              selectedTag = 'All';
              selectedDate = null;
              _searchController.clear();
              searchKeyword = '';
            });
            Navigator.pop(context);
          }, child: const Text('Clear All')),
          ElevatedButton(onPressed: () {
            setState(() {
              selectedTag = tempTag;
              selectedDate = tempDate;
            });
            Navigator.pop(context);
          }, child: const Text('Apply')),
        ],
      ),
    );
  }

  // Help / FAQ
  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('FAQ & Help'),
        content: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            Text('FAQ (singkat):'),
            SizedBox(height: 8),
            Text('- Cipta Topik: Tekan ikon + di atas kanan.'),
            Text('- Edit/Padam: Hanya pemilik topik atau teacher.'),
            Text('- Pin: Hanya teacher.'),
            SizedBox(height: 12),
            Text('Tooltips: Sentuh ikon untuk melihat fungsi.'),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }
}

// Detail page with comments
class ForumDetailPage extends StatefulWidget {
  final String topicId;
  const ForumDetailPage({super.key, required this.topicId});

  @override
  State<ForumDetailPage> createState() => _ForumDetailPageState();
}

class _ForumDetailPageState extends State<ForumDetailPage> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final TextEditingController _commentCtrl = TextEditingController();

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _addComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;

    final user = FirebaseAuth.instance.currentUser;
    final creatorId = user?.uid ?? '';
    final creatorName = user?.displayName ?? user?.email ?? 'Anonymous';

    await _db.collection('forumTopics').doc(widget.topicId).collection('comments').add({
      'text': text,
      'creatorId': creatorId,
      'creatorName': creatorName,
      'timestamp': FieldValue.serverTimestamp(),
      'createdAt': DateTime.now(),
    });
    _commentCtrl.clear();
  }

  DateTime? _toDateTime(dynamic ts) {
    if (ts == null) return null;
    if (ts is Timestamp) return ts.toDate();
    if (ts is DateTime) return ts;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final topicRef = _db.collection('forumTopics').doc(widget.topicId);
    return Scaffold(
      appBar: AppBar(title: const Text('Topic')),
      body: Column(
        children: [
          StreamBuilder<DocumentSnapshot>(
            stream: topicRef.snapshots(),
            builder: (context, snap) {
              if (snap.hasError) return const SizedBox();
              if (!snap.hasData) return const SizedBox();
              final data = (snap.data!.data() as Map<String, dynamic>?) ?? {};
              final title = data['title'] ?? 'Topic';
              final desc = data['description'] ?? '';
              final tag = data['tag'] ?? 'General';
              final edited = data['edited'] == true;
              final editedAt = _toDateTime(data['editedAt']);

              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                    if (edited)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.blueGrey, borderRadius: BorderRadius.circular(6)),
                        child: const Text('Edited', style: TextStyle(color: Colors.white, fontSize: 10)),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  Text(desc),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8.0, children: [Chip(label: Text(tag))]),
                  if (editedAt != null) Text('Edited: ${DateFormat('dd/MM/yyyy HH:mm').format(editedAt)}', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ]),
              );
            },
          ),
          const Divider(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              // order comments by createdAt then fallback to timestamp
              stream: _db.collection('forumTopics').doc(widget.topicId).collection('comments').orderBy('createdAt', descending: false).snapshots(),
              builder: (context, snap) {
                if (snap.hasError) return const Center(child: Text('Error loading comments.'));
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snap.data!.docs;
                if (docs.isEmpty) return const Center(child: Text('No replies yet.'));
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (ctx, i) {
                    final c = docs[i].data() as Map<String, dynamic>;
                    final text = c['text'] ?? '';
                    final ts = _toDateTime(c['timestamp'] ?? c['createdAt']);
                    final creatorName = (c['creatorName'] ?? '').toString().isNotEmpty ? c['creatorName'] as String : 'Anonymous';
                    return ListTile(
                      title: Text(text),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (ts != null) Text(DateFormat('dd/MM/yyyy HH:mm').format(ts)),
                        Text('By: $creatorName', style: const TextStyle(fontSize: 12, color: Colors.black54)),
                      ]),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              child: Row(children: [
                Expanded(child: TextField(controller: _commentCtrl, decoration: const InputDecoration(hintText: 'Write a reply...'))),
                IconButton(icon: const Icon(Icons.send), onPressed: _addComment),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}
