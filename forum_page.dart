// lib/forum_page.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ------------------ ForumPage ------------------
class ForumPage extends StatefulWidget {
  const ForumPage({super.key});

  @override
  State<ForumPage> createState() => _ForumPageState();
}

class _ForumPageState extends State<ForumPage> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  String searchKeyword = '';
  String selectedTag = 'All';
  DateTime? selectedDate;
  String? _userRole; // 'student' or 'teacher'
  String? _userId;
  String? _userName; // optional display name

  final List<String> _tags = ['All', 'Java', 'OOP', 'Algorithm', 'Flutter', 'General'];

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final u = _auth.currentUser;
    if (u == null) {
      // Not logged in — for demo you might redirect to login or continue as guest
      setState(() {
        _userId = null;
        _userRole = 'student'; // fallback
        _userName = 'Anonymous';
      });
      return;
    }

    _userId = u.uid;
    _userName = u.displayName ?? u.email ?? u.uid;

    // Try to load role from 'users' collection (document id = uid, field 'role')
    try {
      final doc = await _db.collection('users').doc(_userId).get();
      if (doc.exists && doc.data() != null && doc.data()!.containsKey('role')) {
        setState(() => _userRole = doc.data()!['role'] as String? ?? 'student');
      } else {
        // default to student
        setState(() => _userRole = 'student');
      }
    } catch (e) {
      setState(() => _userRole = 'student');
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // Create notification (simple broadcast)
  Future<void> _createNotification(String title, String message, String topicId) async {
    await _db.collection('notifications').add({
      'title': title,
      'message': message,
      'topicId': topicId,
      'broadcast': true,
      'timestamp': FieldValue.serverTimestamp(),
    });
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📚 Forum Discussion'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_rounded),
            tooltip: 'Create Topic',
            onPressed: _showCreateTopicDialog,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search + Filter row
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(children: [
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.search),
                  hintText: 'Cari topik forum...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(30)),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
                onChanged: (v) => setState(() => searchKeyword = v.trim().toLowerCase()),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  DropdownButton<String>(
                    value: selectedTag,
                    items: _tags.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                    onChanged: (v) => setState(() => selectedTag = v ?? 'All'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(selectedDate == null ? 'Filter Tarikh' : _formatDate(selectedDate!)),
                  ),
                  const SizedBox(width: 8),
                  TextButton(onPressed: _clearFilters, child: const Text('Clear All')),
                ],
              ),
            ]),
          ),

          // Stream: pinned first, then recent (we order by pinned desc + timestamp desc)
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db
                  .collection('forumTopics')
                  
                  .orderBy('timestamp', descending: true)

                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) return const Center(child: Text('Ralat memuat topik.'));
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());

                final docs = snap.data!.docs.where((doc) {
                  final data = doc.data() as Map<String, dynamic>;
                  final title = (data['title'] ?? '').toString().toLowerCase();
                  final desc = (data['description'] ?? '').toString().toLowerCase();
                  final tag = (data['tag'] ?? 'General').toString();
                  final ts = data['timestamp'] as Timestamp?;
                  final created = ts?.toDate();
                  final searchMatch = title.contains(searchKeyword) || desc.contains(searchKeyword);
                  final tagMatch = (selectedTag == 'All') ? true : (tag.toLowerCase() == selectedTag.toLowerCase());
                  final dateMatch = selectedDate == null
                      ? true
                      : (created != null &&
                          created.year == selectedDate!.year &&
                          created.month == selectedDate!.month &&
                          created.day == selectedDate!.day);
                  return searchMatch && tagMatch && dateMatch;
                }).toList();

                if (docs.isEmpty) return const Center(child: Text('Tiada topik ditemui.'));

                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (ctx, i) {
                    final doc = docs[i];
                    final data = doc.data() as Map<String, dynamic>;
                    final isEdited = data['edited'] == true;
                    final isPinned = data['pinned'] == true;
                    final creatorName = data['creatorName'] ?? 'Anonymous';
                    final creatorId = data['creatorId'] ?? '';
                    final tag = data['tag'] ?? 'General';

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      color: isPinned ? Colors.yellow[50] : null,
                      child: ListTile(
                        title: Row(children: [
                          Expanded(child: Text(data['title'] ?? 'No title')),
                          if (isPinned)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('PIN', style: TextStyle(color: Colors.white, fontSize: 12)),
                            ),
                        ]),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              data['description'] ?? '',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Chip(label: Text(tag)),
                                const SizedBox(width: 8),
                                Text('By $creatorName'),
                                if (isEdited) const Padding(
                                  padding: EdgeInsets.only(left: 8.0),
                                  child: Text('(Edited)', style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          ],
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) async {
                            if (value == 'open') _openPostDetails(doc);
                            else if (value == 'edit') await _tryEditTopic(doc);
                            else if (value == 'delete') await _tryDeleteTopic(doc);
                            else if (value == 'pin') await _togglePin(doc);
                          },
                          itemBuilder: (ctx) {
                            final canEditOrDelete = _userId != null && (_userId == creatorId || _userRole == 'teacher');
                            final canPin = _userRole == 'teacher';
                            return <PopupMenuEntry<String>>[
                              const PopupMenuItem(value: 'open', child: Text('Open')),
                              if (canEditOrDelete) const PopupMenuItem(value: 'edit', child: Text('Edit')),
                              if (canEditOrDelete) const PopupMenuItem(value: 'delete', child: Text('Delete', style: TextStyle(color: Colors.red))),
                              if (canPin) const PopupMenuItem(value: 'pin', child: Text('Pin/Unpin')),
                            ];
                          },
                        ),
                        onTap: () => _openPostDetails(doc),
                      ),
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

  // ---------- Helpers: date picker & formatting ----------
  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: selectedDate ?? DateTime.now(),
    );
    if (picked != null) setState(() => selectedDate = picked);
  }

  String _formatDate(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  void _clearFilters() {
    setState(() {
      _searchController.clear();
      searchKeyword = '';
      selectedTag = 'All';
      selectedDate = null;
    });
  }

  // ---------- Create Topic ----------
  void _showCreateTopicDialog() {
    String tag = _tags.length > 1 ? _tags[1] : 'General';
    _titleController.clear();
    _descController.clear();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Discussion'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(controller: _titleController, decoration: const InputDecoration(labelText: 'Title')),
              const SizedBox(height: 8),
              TextField(controller: _descController, maxLines: 4, decoration: const InputDecoration(labelText: 'Description')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: tag,
                items: _tags.where((t) => t != 'All').map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => tag = v ?? tag,
                decoration: const InputDecoration(labelText: 'Tag'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final title = _titleController.text.trim();
              final desc = _descController.text.trim();
              if (title.isEmpty || desc.isEmpty) return;

              final docRef = await _db.collection('forumTopics').add({
                'title': title,
                'description': desc,
                'tag': tag,
                'creatorId': _userId ?? '',
                'creatorName': _userName ?? '',
                'timestamp': FieldValue.serverTimestamp(),
                'edited': false,
                'pinned': false,
              });

              // create simple notification (broadcast)
              await _createNotification('New forum topic', '$title', docRef.id);

              Navigator.pop(context);
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  // ---------- Try Edit (check permission) ----------
  Future<void> _tryEditTopic(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final creatorId = data['creatorId'] ?? '';
    if (_userId == null) {
      _showToast('Sila log masuk untuk mengedit topik.');
      return;
    }
    if (_userId != creatorId && _userRole != 'teacher') {
      _showToast('Anda tidak dibenarkan mengedit topik ini.');
      return;
    }
    _editTopic(doc);
  }

  Future<void> _editTopic(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    _titleController.text = data['title'] ?? '';
    _descController.text = data['description'] ?? '';
    String tag = data['tag'] ?? _tags[1];

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Topic'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(controller: _titleController, decoration: const InputDecoration(labelText: 'Title')),
              const SizedBox(height: 8),
              TextField(controller: _descController, maxLines: 4, decoration: const InputDecoration(labelText: 'Description')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: tag,
                items: _tags.where((t) => t != 'All').map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => tag = v ?? tag,
                decoration: const InputDecoration(labelText: 'Tag'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final newTitle = _titleController.text.trim();
              final newDesc = _descController.text.trim();
              if (newTitle.isEmpty || newDesc.isEmpty) return;

              await _db.collection('forumTopics').doc(doc.id).update({
                'title': newTitle,
                'description': newDesc,
                'tag': tag,
                'edited': true,
                'editedAt': FieldValue.serverTimestamp(),
              });

              // notification for edit
              await _createNotification('Topik dikemaskini', newTitle, doc.id);

              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ---------- Try Delete ----------
  Future<void> _tryDeleteTopic(QueryDocumentSnapshot doc) async {
    final data = doc.data() as Map<String, dynamic>;
    final creatorId = data['creatorId'] ?? '';
    if (_userId == null) {
      _showToast('Sila log masuk untuk memadam topik.');
      return;
    }
    if (_userId != creatorId && _userRole != 'teacher') {
      _showToast('Anda tidak dibenarkan memadam topik ini.');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: const Text('Adakah anda pasti mahu memadam topik ini?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _db.collection('forumTopics').doc(doc.id).delete();
      // optional: delete subcollection comments (not implemented here)
      _showToast('Topik dipadamkan.');
    }
  }

  // ---------- Pin / Unpin (teacher only) ----------
  Future<void> _togglePin(QueryDocumentSnapshot doc) async {
    if (_userRole != 'teacher') {
      _showToast('Hanya teacher boleh pin/unpin topik.');
      return;
    }
    final data = doc.data() as Map<String, dynamic>;
    final isPinned = data['pinned'] == true;
    await _db.collection('forumTopics').doc(doc.id).update({'pinned': !isPinned});
    _showToast(isPinned ? 'Topik unpinned.' : 'Topik pinned.');
  }

  // ---------- Open detail page (with comments) ----------
  void _openPostDetails(QueryDocumentSnapshot post) {
    Navigator.push(context, MaterialPageRoute(builder: (_) => ForumDetailPage(post: post, currentUserId: _userId ?? '')));
  }

  // ---------- Small helper ----------
  void _showToast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

// ------------------ Forum Detail Page (simple comments) ------------------
class ForumDetailPage extends StatefulWidget {
  final QueryDocumentSnapshot post;
  final String currentUserId;
  const ForumDetailPage({super.key, required this.post, required this.currentUserId});

  @override
  State<ForumDetailPage> createState() => _ForumDetailPageState();
}

class _ForumDetailPageState extends State<ForumDetailPage> {
  final _db = FirebaseFirestore.instance;
  final TextEditingController _commentCtrl = TextEditingController();

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  Future<void> _addComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    final topicId = widget.post.id;

    await _db.collection('forumTopics').doc(topicId).collection('comments').add({
      'text': text,
      'authorId': widget.currentUserId,
      'timestamp': FieldValue.serverTimestamp(),
    });

    // Create a broadcast notification for demo (in real app target subscribers)
    await _db.collection('notifications').add({
      'title': 'New reply',
      'message': 'A new reply was posted in "${widget.post['title']}"',
      'topicId': topicId,
      'broadcast': true,
      'timestamp': FieldValue.serverTimestamp(),
    });

    _commentCtrl.clear();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.post.data() as Map<String, dynamic>;
    final title = data['title'] ?? '';
    final desc = data['description'] ?? '';
    final tag = data['tag'] ?? 'General';
    final isEdited = data['edited'] == true;
    final editedAt = (data['editedAt'] as Timestamp?)?.toDate();

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(
                children: [
                  Chip(label: Text(tag)),
                  const SizedBox(width: 8),
                  if (isEdited) const Text('(Edited)', style: TextStyle(color: Colors.red)),
                  if (editedAt != null) const SizedBox(width: 8),
                  if (editedAt != null) Text('Edited: ${editedAt.toLocal()}'),
                ],
              ),
              const SizedBox(height: 12),
              Text(desc),
            ]),
          ),
          const Divider(),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _db.collection('forumTopics').doc(widget.post.id).collection('comments').orderBy('timestamp', descending: false).snapshots(),
              builder: (context, snap) {
                if (!snap.hasData) return const Center(child: CircularProgressIndicator());
                final docs = snap.data!.docs;
                if (docs.isEmpty) return const Center(child: Text('No replies yet.'));
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (ctx, i) {
                    final c = docs[i].data() as Map<String, dynamic>;
                    final text = c['text'] ?? '';
                    final author = c['authorId'] ?? 'unknown';
                    final t = (c['timestamp'] as Timestamp?)?.toDate();
                    return ListTile(
                      title: Text(text),
                      subtitle: Text('By $author ${t != null ? '· ${t.toLocal()}' : ''}'),
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
              child: Row(
                children: [
                  Expanded(child: TextField(controller: _commentCtrl, decoration: const InputDecoration(hintText: 'Write a reply...'))),
                  IconButton(icon: const Icon(Icons.send), onPressed: _addComment),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
