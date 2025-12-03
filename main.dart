..._questions.asMap().entries.map((entry) {
  int idx = entry.key;
  Question q = entry.value;
  return Card(
    margin: const EdgeInsets.symmetric(vertical: 6),
    child: ListTile(
      title: Text(
        'Q${idx + 1}: ${q.questionText}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Type: ${q.type == QuestionType.mcq ? "MCQ" : "Short Answer"}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          Text(
            'Answer: ${q.answer}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ✅ NEW: Edit button
          IconButton(
            icon: const Icon(Icons.edit, color: Colors.blue),
            tooltip: 'Edit Question',
            onPressed: () => _showEditQuestionDialog(idx),
          ),
          // Delete button
          IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            tooltip: 'Delete Question',
            onPressed: () => setState(() => _questions.removeAt(idx)),
          ),
        ],
      ),
    ),
  );
}),
