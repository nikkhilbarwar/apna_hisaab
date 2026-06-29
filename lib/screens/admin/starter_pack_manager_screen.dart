import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../providers/profile_provider.dart';
import 'pack_editor_screen.dart';
import '../../core/widgets/app_bottom_sheet.dart';

class StarterPackManagerScreen extends StatefulWidget {
  const StarterPackManagerScreen({super.key});

  @override
  State<StarterPackManagerScreen> createState() => _StarterPackManagerScreenState();
}

class _StarterPackManagerScreenState extends State<StarterPackManagerScreen> {
  @override
  Widget build(BuildContext context) {
    final profile = Provider.of<ProfileProvider>(context);
    final appBarColor = ThemeData.estimateBrightnessForColor(profile.themeColor) == Brightness.dark
        ? Colors.white
        : Colors.black;
    
    return Scaffold(
      backgroundColor: profile.scaffoldColor,
      appBar: AppBar(
        title: const Text("Starter Pack Manager", style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: profile.themeColor,
        foregroundColor: appBarColor,
        elevation: 0,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: profile.themeColor.withValues(alpha: 0.1),
            child: Row(
              children: [
                Icon(Icons.auto_awesome_motion_rounded, color: profile.themeColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "Manage business templates. These packs help new users setup their inventory instantly.",
                    style: TextStyle(fontSize: 12, color: profile.secondaryTextColor),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('starter_packs')
                  .orderBy('updatedAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) return Center(child: Text("Error: ${snapshot.error}"));
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final packs = snapshot.data?.docs ?? [];
                if (packs.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2_outlined, size: 64, color: profile.secondaryTextColor.withValues(alpha: 0.3)),
                        const SizedBox(height: 16),
                        Text("No Starter Packs Found", style: TextStyle(color: profile.secondaryTextColor)),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: () => _editPack(context, null),
                          icon: const Icon(Icons.add),
                          label: const Text("CREATE FIRST PACK"),
                          style: ElevatedButton.styleFrom(backgroundColor: profile.themeColor, foregroundColor: Colors.white),
                        )
                      ],
                    ),
                  );
                }

                return ListView.builder(
                  itemCount: packs.length,
                  padding: const EdgeInsets.all(16),
                  itemBuilder: (context, index) {
                    final doc = packs[index];
                    final pack = doc.data() as Map<String, dynamic>;
                    final name = pack['packName'] ?? 'Unnamed Pack';
                    final catCount = (pack['categories'] as List?)?.length ?? 0;
                    final itemCount = (pack['items'] as List?)?.length ?? 0;

                    return Card(
                      color: profile.cardColor,
                      elevation: 0,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: profile.isDarkMode ? Colors.white10 : Colors.grey.shade200),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        leading: CircleAvatar(
                          backgroundColor: profile.themeColor.withValues(alpha: 0.1),
                          child: Icon(Icons.business_center_rounded, color: profile.themeColor),
                        ),
                        title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle: Text("$catCount Categories • $itemCount Pre-defined Items", style: const TextStyle(fontSize: 12)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit_note_rounded, color: Colors.blue),
                              onPressed: () => _editPack(context, pack),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.red),
                              onPressed: () => _confirmDelete(context, doc.id, name, profile),
                            ),
                          ],
                        ),
                        onTap: () => _editPack(context, pack),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editPack(context, null),
        backgroundColor: profile.themeColor,
        label: const Text("NEW PACK", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        icon: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  void _editPack(BuildContext context, Map<String, dynamic>? pack) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PackEditorScreen(pack: pack),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, String docId, String name, ProfileProvider profile) async {
    final confirm = await AppBottomSheet.showAction(
      context: context,
      profile: profile,
      title: "Delete Starter Pack?",
      message: "Are you sure you want to delete '$name'? This template will no longer be available for new users.",
      confirmLabel: "DELETE PERMANENTLY",
    );

    if (confirm == true) {
      await FirebaseFirestore.instance.collection('starter_packs').doc(docId).delete();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pack Deleted")));
      }
    }
  }
}
