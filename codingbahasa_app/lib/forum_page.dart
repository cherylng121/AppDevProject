import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class ForumPage extends StatefulWidget {
  const ForumPage({super.key});

  @override
  State<ForumPage> createState() => _ForumPageState();
}

class _ForumPageState extends State<ForumPage> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  String searchKeyword = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('💬 Forum Discussion'),
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
          // 🔍 Search Bar
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search forum topics...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
                filled: true,
                fillColor: Colors.grey[100],
              ),
              onChanged: (value) {
                setState(() => searchKeyword = value.trim().toLowerCase());
              },
            ),
          ),

          // 🧾 Forum List (Firestore Stream)
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('forumTopics')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('Error loading posts.'));
                }
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final posts = snapshot.data!.docs.where((doc) {
                  final title = (doc['title'] ?? '').toString().toLowerCase();
                  final desc = (doc['description'] ?? '').toString().toLowerCase();
                  return title.contains(searchKeyword) ||
                      desc.contains(searchKeyword);
                }).toList();

                if (posts.isEmpty) {
                  return const Center(
                    child: Text('No matching topics found.'),
                  );
                }

                return ListView.builder(
                  itemCount: posts.length,
                  itemBuilder: (context, index) {
                    final post = posts[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      child: ListTile(
                        title: Text(post['title'] ?? 'No title'),
                        subtitle: Text(
                          post['description'] ?? 'No description',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                        onTap: () {
                          _openPostDetails(post);
                        },
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

  // 🧠 Create Topic Dialog
  void _showCreateTopicDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create New Discussion'),
        content: SingleChildScrollView(
          child: Column(
            children: [
              TextField(
                controller: _titleController,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _descController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: _submitTopic,
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  // 📝 Submit new topic to Firestore
  Future<void> _submitTopic() async {
    final title = _titleController.text.trim();
    final desc = _descController.text.trim();
    if (title.isEmpty || desc.isEmpty) return;

    await FirebaseFirestore.instance.collection('forumTopics').add({
      'title': title,
      'description': desc,
      'timestamp': FieldValue.serverTimestamp(),
    });

    _titleController.clear();
    _descController.clear();
    Navigator.pop(context);
  }

  // 📄 View topic details
  void _openPostDetails(QueryDocumentSnapshot post) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ForumDetailPage(post: post),
      ),
    );
  }
}

// ========== Forum Detail Page ==========
class ForumDetailPage extends StatelessWidget {
  final QueryDocumentSnapshot post;
  const ForumDetailPage({super.key, required this.post});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(post['title'] ?? 'Topic')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(post['description'] ?? 'No description'),
      ),
    );
  }
}
